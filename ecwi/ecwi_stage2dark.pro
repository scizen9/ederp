;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_STAGE2DARK
;
; PURPOSE:
;	This procedure takes the output from ECWI_STAGE1 and subtracts the
;	master dark frame.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_STAGE2DARK, Pparfname, Linkfname
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
;	PROC_DARKNUMS - set to the corresponding master dark image numbers
;	NOTE: PROC_IMGNUMS and PROC_DARKNUMS must have the same number of items
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
;	'dark.link' file in output directory to derive the list
;	of input files and their associated master dark files.  Each input
;	file is read in and the required master dark is generated before
;	subtraction.
;
; EXAMPLE:
;	Perform stage2dark reductions on the images in 'night1' directory and 
;	put results in 'night1/redux':
;
;	ECWI_STAGE2DARK,'night1/redux/ecwi.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-MAY-10	Initial version
;	2013-SEP-14	Use ppar to pass loglun
;	2014-APR-01	Now scale dark by exposure time
;	2014-APR-03	Uses master ppar and link files
;	2014-SEP-29	Added infrastructure to handle selected processing
;-
pro ecwi_stage2dark,ppfname,linkfname,help=help,select=select, $
	proc_imgnums=proc_imgnums, proc_darknums=proc_darknums, $
	verbose=verbose, display=display
	;
	; setup
	pre = 'ECWI_STAGE2DARK'
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
		if n_elements(proc_darknums) ne nproc then begin
			ecwi_print_info,ppar,pre,'Number of darks must equal number of images',/error
			return
		endif
		imgnum = proc_imgnums
		dnums = proc_darknums
	;
	; if not use link file
	endif else begin
		;
		; read link file
		ecwi_read_links,ppar,linkfname,imgnum,dark=dnums,count=nproc, $
			select=select
		if imgnum[0] lt 0 then begin
			ecwi_print_info,ppar,pre,'reading link file',/error
			return
		endif
	endelse
	;
	; log file
	lgfil = reddir + 'ecwi_stage2dark.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+ecwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ppar.datdir
	printf,ll,'Ppar file: '+ppar.ppfname
	if keyword_set(proc_imgnums) then begin
		printf,ll,'Processing images: ',imgnum
		printf,ll,'Using these darks: ',dnums
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
		; image to process (in reduced dir)
		obfil = ecwi_get_imname(ppar,imgnum[i],'_int',/reduced)
		;
		; check input file
		if file_test(obfil) then begin
			;
			; read configuration
			ecfg = ecwi_read_cfg(obfil)
			;
			; final output file
			ofil = ecwi_get_imname(ppar,imgnum[i],'_intd',/reduced)
			;
			; trim image type
			ecfg.imgtype = strtrim(ecfg.imgtype,2)
			;
			; check if output file exists already
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
				; get exposure time
				exptime = sxpar(hdr,'EXPTIME')
				;
				; read variance, mask images
				vfil = ecwi_get_imname(ppar,imgnum[i],'_var',/reduced)
				if file_test(vfil) then begin
					var = mrdfits(vfil,0,varhdr,/fscale,/silent)
				endif else begin
					var = fltarr(sz)
					var[0] = 1.	; give value range
					varhdr = hdr
					ecwi_print_info,ppar,pre, $
					    'variance image not found for: '+ $
					    obfil,/warning
				endelse
				mfil = ecwi_get_imname(ppar,imgnum[i],'_msk',/reduced)
				if file_test(mfil) then begin
					msk = mrdfits(mfil,0,mskhdr,/silent)
				endif else begin
					msk = intarr(sz)
					msk[0] = 1	; give value range
					mskhdr = hdr
					ecwi_print_info,ppar,pre, $
					    'mask image not found for: '+ $
					    obfil,/warning
				endelse
				;
				;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
				; STAGE 2: DARK SUBTRACTION
				;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
				;
				; do we have a dark link?
				do_dark = (1 eq 0)	; assume no to begin with
				if dnums[i] ge 0 then begin
					;
					; master dark file name
					;mdfile = cdir + 'mdark_' + strn(dnums[i]) + '.fits'
					mdfile = cdir + 'mdark_' + string(dnums[i],'(i0'+strn(ppar.fdigits)+')') + '.fits'
					;
					; master dark image ppar filename
					mdppfn = strmid(mdfile,0,strpos(mdfile,'.fits')) + '.ppar'
					;
					; check access
					if file_test(mdppfn) then begin
						do_dark = (1 eq 1)
						;
						; log that we got it
						ecwi_print_info,ppar,pre,'dark file = '+mdfile
					endif else begin
						;
						; log that we haven't got it
						ecwi_print_info,ppar,pre,'dark file not found: '+mdfile,/error
					endelse
				endif
				;
				; let's read in or create master dark
				if do_dark then begin
					;
					; build master dark if necessary
					if not file_test(mdfile) then begin
						;
						; build master dark
					 	dpar = ecwi_read_ppar(mdppfn)
						dpar.loglun  = ppar.loglun
						dpar.verbose = ppar.verbose
						dpar.display = ppar.display
						ecwi_make_dark,dpar
					endif
					;
					; read in master dark
					mdark = mrdfits(mdfile,0,mdhdr,/fscale,/silent)
					;
					; get exposure time
					dexptime = sxpar(mdhdr,'EXPTIME')
					;
					; read in master dark variance
					mdvarfile = strmid(mdfile,0,strpos(mdfile,'.fit')) + '_var.fits'
					mdvar = mrdfits(mdvarfile,0,mvhdr,/fscale,/silent)
					;
					; read in master dark mask
					mdmskfile = strmid(mdfile,0,strpos(mdfile,'.fit')) + '_msk.fits'
					mdmsk = mrdfits(mdmskfile,0,mmhdr,/fscale,/silent)
					;
					; scale by exposure time
					fac = 1.0
					if exptime gt 0. and dexptime gt 0. then $
						fac = exptime/dexptime $
					else	ecwi_print_info,ppar,pre,'unable to scale dark by exposure time',/warning
					;
					; do subtraction
					img = img - mdark*fac
					;
					; handle variance
					var = var + mdvar
					;
					; handle mask
					msk = msk + mdmsk
					;
					; update header
					sxaddpar,mskhdr,'COMMENT','  '+pre+' '+systime(0)
					sxaddpar,mskhdr,'DARKSUB','T',' dark subtracted?'
					sxaddpar,mskhdr,'MDFILE',mdfile,' master dark file applied'
					sxaddpar,mskhdr,'DARKSCL',fac,' dark scale factor'
					;
					; write out mask image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_mskd',/nodir)
					ecwi_write_image,msk,mskhdr,ofil,ppar
					;
					; update header
					sxaddpar,varhdr,'COMMENT','  '+pre+' '+systime(0)
					sxaddpar,varhdr,'DARKSUB','T',' dark subtracted?'
					sxaddpar,varhdr,'MDFILE',mdfile,' master dark file applied'
					sxaddpar,varhdr,'DARKSCL',fac,' dark scale factor'
					;
					; output variance image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_vard',/nodir)
					ecwi_write_image,var,varhdr,ofil,ppar
					;
					; update header
					sxaddpar,hdr,'COMMENT','  '+pre+' '+systime(0)
					sxaddpar,hdr,'DARKSUB','T',' dark subtracted?'
					sxaddpar,hdr,'MDFILE',mdfile,' master dark file applied'
					sxaddpar,hdr,'DARKSCL',fac,' dark scale factor'
					;
					; write out final intensity image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_intd',/nodir)
					ecwi_write_image,img,hdr,ofil,ppar
					;
					; handle the case when no dark frames were taken
				endif else begin
					ecwi_print_info,ppar,pre,'cannot associate with any master dark: '+ $
						ecfg.obsfname,/warning
				endelse
				flush,ll
			;
			; end check if output file exists already
			endif else begin
				ecwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+ecfg.imgtype,/warning
				if ppar.clobber eq 0 and file_test(ofil) then $
					ecwi_print_info,ppar,pre,'processed file exists already: '+ofil,/warning
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
