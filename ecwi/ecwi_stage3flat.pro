;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_STAGE3FLAT
;
; PURPOSE:
;	This procedure takes the output from ECWI_STAGE1 and applies further
;	processing that includes: flat field correction and nod-and-shuffle
;	sky subtraction.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_STAGE3FLAT, Pparfname, Linkfname
;
; OPTIONAL INPUTS:
;	Pparfname - input ppar filename generated by ECWI_PREP
;			defaults to './redux/ecwi.ppar'
;	Linkfname - input link filename generated by ECWI_PREP
;			defaults to './redux/ecwi.link'
;
; KEYWORDS:
;	SELECT	- set this keyword to select a specific image to process
;	PROC_IMGNUMS - set to the specific image numbers you want to process
;	PROC_FLATNUMS - set to the corresponding master dark image numbers
;	NOTE: PROC_IMGNUMS and PROC_FLATNUMS must have the same number of items
;	VERBOSE	- set to verbosity level to override value in ppar file
;	DISPLAY - set to display level to override value in ppar file
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	Outputs processed files in output directory specified by the
;	ECWI_PPAR struct read in from Pparfname.
;
; PROCEDURE:
;	Reads Pparfname to derive input/output directories and reads the
;	corresponding '*.link' file in output directory to derive the list
;	of input files and their associated master flat files.  Each input
;	file is read in and the required master flat is generated and 
;	fit and multiplied.  If the input image is a nod-and-shuffle
;	observation, the image is sky subtracted and then the flat is applied.
;
; EXAMPLE:
;	Perform stage3flat reductions on the images in 'night1' directory and put
;	results in 'night1/redux':
;
;	ECWI_STAGE3FLAT,'night1/redux/ecwi.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-SEP-10	Initial version
;	2013-SEP-11	Added variance calculation
;	2013-SEP-14	Use ppar to pass loglun
;	2014-APR-03	Use master ppar and link files
;	2014-SEP-29	Added infrastructure to handle selected processing
;-
pro ecwi_stage3flat,ppfname,linkfname,help=help,select=select, $
	proc_imgnums=proc_imgnums, proc_flatnums=proc_flatnums, $
	verbose=verbose, display=display
	;
	; setup
	pre = 'ECWI_STAGE3FLAT'
	startime=systime(1)
	q = ''	; for queries
	;
	; help request
	if keyword_set(help) then begin
		print,pre+': Info - Usage: '+pre+', Ppar_filespec, Link_filespec'
		print,pre+': Info - default filespecs usually work (i.e., leave them off)'
		return
	endif
	;
	; get ppar struct
	ppar = ecwi_read_ppar(ppfname)
	;
	; verify ppar
	if ecwi_verify_ppar(ppar,/init) ne 0 then begin
		print,pre+': Error - pipeline parameter file not initialized: ',ppfname
		return
	endif
	;
	; directories
	if ecwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir,/nocreate) ne 0 then begin
		ecwi_print_info,ppar,pre,'Directory error, returning',/error
		return
	endif
	;
	; check keyword overrides
	if n_elements(verbose) eq 1 then $
		ppar.verbose = verbose
	if n_elements(display) eq 1 then $
		ppar.display = display
	;
	; specific images requested?
	if keyword_set(proc_imgnums) then begin
		nproc = n_elements(proc_imgnums)
		if n_elements(proc_flatnums) ne nproc then begin
			ecwi_print_info,ppar,pre,'Number of flats must equal number of images',/error
			return
		endif
		imgnum = proc_imgnums
		fnums = proc_flatnums
	;
	; if not use link file
	endif else begin
		;
		; read link file
		ecwi_read_links,ppar,linkfname,imgnum,flat=fnums,count=nproc, $
			select=select
		if imgnum[0] lt 0 then begin
			ecwi_print_info,ppar,pre,'reading link file',/error
			return
		endif
	endelse
	;
	; log file
	lgfil = reddir + 'ecwi_stage3flat.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+ecwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ddir
	printf,ll,'Ppar file: '+ppar.ppfname
	if keyword_set(proc_imgnums) then begin
		printf,ll,'Processing images: ',imgnum
		printf,ll,'Using these flats: ',fnums
	endif else $
		printf,ll,'Master link file: '+linkfname
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Display level     : ',ppar.display
	;
	; gather configuration data on each observation in reddir
	ecwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process
		;
		; check for dark subtracted image first
		obfil = ecwi_get_imname(ppar,imgnum[i],'_intd',/reduced)
		;
		; if not just get stage1 output image
		if not file_test(obfil) then $
			obfil = ecwi_get_imname(ppar,imgnum[i],'_int',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			ecfg = ecwi_read_cfg(obfil)
			;
			; final output file
			ofil = ecwi_get_imname(ppar,imgnum[i],'_intf',/reduced)
			;
			; trim image type
			ecfg.imgtype = strtrim(ecfg.imgtype,2)
			;
			; check of output file exists already
			if ppar.clobber eq 1 or not file_test(ofil) then begin
				;
				; print image summary
				ecwi_print_cfgs,ecfg,imsum,/silent
				if strlen(imsum) gt 0 then begin
					for k=0,1 do junk = gettok(imsum,' ')
					imsum = string(i+1,'/',nproc,format='(i3,a1,i3)')+' '+imsum
				endif
				print,""
				print,imsum
				printf,ll,""
				printf,ll,imsum
				flush,ll
				;
				; read in image
				img = mrdfits(obfil,0,hdr,/fscale,/silent)
				;
				; get dimensions
				sz = size(img,/dimension)
				;
				; read variance, mask images
				vfil = repstr(obfil,'_int','_var')
				if file_test(vfil) then begin
					var = mrdfits(vfil,0,varhdr,/fscale,/silent)
				endif else begin
					var = fltarr(sz)
					var[0] = 1.	; give var value range
					varhdr = hdr
					ecwi_print_info,ppar,pre,'variance image not found for: '+obfil,/warning
				endelse
				mfil = repstr(obfil,'_int','_msk')
				if file_test(mfil) then begin
					msk = mrdfits(mfil,0,mskhdr,/silent)
				endif else begin
					msk = intarr(sz)
					msk[0] = 1	; give mask value range
					mskhdr = hdr
					ecwi_print_info,ppar,pre,'mask image not found for: '+obfil,/warning
				endelse
				;
				;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
				; STAGE 3: FLAT CORRECTION
				;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
				;
				; do we have a flat link?
				do_flat = (1 eq 0)	; assume no to begin with
				if fnums[i] ge 0 then begin
					;
					; master flat file name
					;mffile = cdir + 'mflat_' + $
					;      strn(fnums[i],padtype=1,padchar='0',length=ppar.fdigits) + '.fits'
					mffile = cdir + 'mflat_' + string(fnums[i],'(i0'+strn(ppar.fdigits)+')') + '.fits'
					;
					; master flat image ppar filename
					mfppfn = strmid(mffile,0,strpos(mffile,'.fits')) + '.ppar'
					;
					; check access
					if file_test(mfppfn) then begin
						do_flat = (1 eq 1)
						;
						; log that we got it
						ecwi_print_info,ppar,pre,'flat file = '+mffile
					endif else begin
						;
						; log that we haven't got it
						ecwi_print_info,ppar,pre,'flat file not found: '+mffile,/error
					endelse
				endif
				;
				; let's read in or create master flat
				if do_flat then begin
					;
					; build master flat if necessary
					if not file_test(mffile) then begin
						;
						; build master flat
						fpar = ecwi_read_ppar(mfppfn)
						fpar.loglun  = ppar.loglun
						fpar.verbose = ppar.verbose
						fpar.display = ppar.display
						ecwi_make_flat,fpar
					endif
					;
					; read in master flat
					mflat = mrdfits(mffile,0,mfhdr,/fscale,/silent)
					;
					; do correction
					img = img * mflat
					;
					; variance is multiplied by flat squared
					var = var * mflat^2
					;
					; update header
					sxaddpar,mskhdr,'COMMENT','  '+pre+' '+systime(0)
					sxaddpar,mskhdr,'FLATCOR','T',' flat corrected?'
					sxaddpar,mskhdr,'MFFILE',mffile,' master flat file applied'
					;
					; write out final intensity image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_mskf',/nodir)
					ecwi_write_image,msk,mskhdr,ofil,ppar
					;
					; update header
					sxaddpar,varhdr,'COMMENT','  '+pre+' '+systime(0)
					sxaddpar,varhdr,'FLATCOR','T',' flat corrected?'
					sxaddpar,varhdr,'MFFILE',mffile,' master flat file applied'
					;
					; write out mask image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_varf',/nodir)
					ecwi_write_image,var,varhdr,ofil,ppar
					;
					; update header
					sxaddpar,hdr,'COMMENT','  '+pre+' '+systime(0)
					sxaddpar,hdr,'FLATCOR','T',' flat corrected?'
					sxaddpar,hdr,'MFFILE',mffile,' master flat file applied'
					;
					; write out final intensity image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_intf',/nodir)
					ecwi_write_image,img,hdr,ofil,ppar
					;
					; handle the case when no flat frames were taken
				endif else begin
					ecwi_print_info,ppar,pre,'cannot associate with any master flat: '+ $
						ecfg.obsfname,/warning
				endelse
				flush,ll
			;
			; end check if output file exists already
			endif else begin
				ecwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+ecfg.imgtype,/warning
				if ppar.clobber eq 0 and file_test(ofil) then $
					ecwi_print_info,ppar,pre,'processed file exists already',/warning
			endelse
		;
		; end check if input file exists
		endif else $
			ecwi_print_info,ppar,pre,'input file not found: '+obfil,/error
	endfor	; loop over images
	;
	; report
	eltime = systime(1) - startime
	print,''
	printf,ll,''
	ecwi_print_info,ppar,pre,'run time in seconds',eltime
	ecwi_print_info,ppar,pre,'finished on '+systime(0)
	;
	; close log file
	free_lun,ll
	;
	return
end
