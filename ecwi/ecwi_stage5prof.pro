;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_STAGE5PROF
;
; PURPOSE:
;	This procedure takes the output from ECWI_STAGE4GEOM and applies 
;	a slice profile correction.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_STAGE5PROF, Pparfname, Linkfname
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
;	PROC_PROFNUMS - set to the corresponding master dark image numbers
;	NOTE: PROC_IMGNUMS and PROC_PROFNUMS must have the same number of items
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
;	of input files and their associated profile files.  Each input
;	file is read in and the required profile is generated and 
;	divided out of the observation.
;
; EXAMPLE:
;	Perform stage5prof reductions on the images in 'night1' directory and 
;	put results in 'night1/redux':
;
;	ECWI_STAGE5PROF,'night1/redux/prof.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-SEP-23	Initial version
;	2014-APR-05	Use master ppar and link files
;	2014-APR-06	Apply to nod-and-shuffle sky and obj cubes
;	2014-MAY-13	Include calibration image numbers in headers
;	2014-SEP-29	Added infrastructure to handle selected processing
;-
pro ecwi_stage5prof,ppfname,linkfname,help=help,select=select, $
	proc_imgnums=proc_imgnums, proc_profnums=proc_profnums, $
	verbose=verbose, display=display
	;
	; setup
	pre = 'ECWI_STAGE5PROF'
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
		if n_elements(proc_profnums) ne nproc then begin
			ecwi_print_info,ppar,pre,'Number of profiles must equal number of images',/error
			return
		endif
		imgnum = proc_imgnums
		pnums = proc_profnums
	;
	; if not use link file
	endif else begin
		;
		; read link file
		ecwi_read_links,ppar,linkfname,imgnum,prof=pnums,count=nproc, $
			select=select
		if imgnum[0] lt 0 then begin
			ecwi_print_info,ppar,pre,'reading link file',/error
			return
		endif
	endelse
	;
	; log file
	lgfil = reddir + 'ecwi_stage5prof.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+ecwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ddir
	printf,ll,'Filespec: '+ppar.filespec
	printf,ll,'Ppar file: '+ppar.ppfname
	if keyword_set(proc_imgnums) then begin
		printf,ll,'Processing images: ',imgnum
		printf,ll,'Using these profs: ',pnums
	endif else $
		printf,ll,'Master link file: '+linkfname
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Plot display level: ',ppar.display
	;
	; gather configuration data on each observation in reddir
	ecwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process
		;
		; require output from ecwi_stage4geom
		obfil = ecwi_get_imname(ppar,imgnum[i],'_icube',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			ecfg = ecwi_read_cfg(obfil)
			;
			; final output file
			ofil = ecwi_get_imname(ppar,imgnum[i],'_icubep',/reduced)
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
				; do we have a prof link (also must have a cube)?
				do_prof = (1 eq 0)
				if pnums[i] ge 0 then begin
					;
					; get filename
					prf = ecwi_get_imname(ppar,pnums[i],/nodir)
					;
					; corresponding master prof file name
					mpfile = cdir + strmid(prf,0,strpos(prf,'.fit'))+'_prof.fits'
					;
					; is prof file already built?
					if file_test(mpfile) then begin
						do_prof = (1 eq 1)
						;
						; log that we got it
						ecwi_print_info,ppar,pre,'slice profile file = '+mpfile
					endif else begin
						;
						; does input prof image exist?
						pinfile = ecwi_get_imname(ppar,pnums[i],'_icube',/reduced)
						if file_test(pinfile) then begin
							do_prof = (1 eq 1)
							ecwi_print_info,ppar,pre,'building slice profile file = '+mpfile
						endif else begin
							;
							; log that we haven't got it
							ecwi_print_info,ppar,pre,'slice profile input file not found: '+pinfile,/warning
						endelse
					endelse
				endif
				;
				; let's read in or create master prof
				if do_prof then begin
					;
					; build master prof if necessary
					if not file_test(mpfile) then begin
						;
						; get observation info
						pcfg = ecwi_read_cfg(pinfile)
						;
						; build master prof
						ecwi_slice_prof,pcfg,ppar
					endif
					;
					; read in master prof
					mprof = mrdfits(mpfile,0,mphdr,/fscale,/silent)
					;
					; get master prof image number
					mpimgno = sxpar(mphdr,'IMGNUM')
					;
					; get dimensions
					mpsz = size(mprof,/dimension)
					;
					; read in image
					img = mrdfits(obfil,0,hdr,/fscale,/silent)
					;
					; get dimensions
					sz = size(img,/dimension)
					;
					; check dimension compatability
					if sz[0] ne mpsz[0] then $
						ecwi_print_info,ppar,pre,'image/profile size mis-match: img x, prof x', $
							sz[0],mpsz[0],format='(a,2i7)',/warning
					;
					; adjust mprof accordingly
					if sz[0] gt mpsz[0] then begin
						tmp = fltarr(sz[0],12) + 1.
						tmp[0:(mpsz[0]-1),*] = mprof
						mprof = tmp
					endif else if sz[0] lt mpsz[0] then begin
						mprof = mprof[0:(sz[0]-1),*]
					endif
					;
					; read variance, mask images
					vfil = repstr(obfil,'_icube','_vcube')
					if file_test(vfil) then begin
						var = mrdfits(vfil,0,varhdr,/fscale,/silent)
					endif else begin
						var = fltarr(sz)
						var[0] = 1.	; give var value range
						varhdr = hdr
						ecwi_print_info,ppar,pre,'variance image not found for: '+obfil,/warning
					endelse
					mfil = repstr(obfil,'_icube','_mcube')
					if file_test(mfil) then begin
						msk = mrdfits(mfil,0,mskhdr,/silent)
					endif else begin
						msk = intarr(sz)
						msk[0] = 1	; give mask value range
						mskhdr = hdr
						ecwi_print_info,ppar,pre,'mask image not found for: '+obfil,/warning
					endelse
					;
					; do correction
					for is=0,11 do begin
						for iy = 0, sz[2]-1 do begin
							img[*,is,iy] = img[*,is,iy] / mprof[*,is]
							;
							; variance is multiplied by prof squared
							var[*,is,iy] = var[*,is,iy] * mprof[*,is]^2
						endfor
					endfor
					;
					; update header
					sxaddpar,mskhdr,'COMMENT','  '+pre+' '+systime(0)
					sxaddpar,mskhdr,'PROFCOR','T',' prof corrected?'
					sxaddpar,mskhdr,'MPFILE',mpfile,' master prof file applied'
					sxaddpar,mskhdr,'MPIMNO',mpimgno,' master prof image number'
					;
					; write out mask image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_mcubep',/nodir)
					ecwi_write_image,msk,mskhdr,ofil,ppar
					;
					; update header
					sxaddpar,varhdr,'COMMENT','  '+pre+' '+systime(0)
					sxaddpar,varhdr,'PROFCOR','T',' prof corrected?'
					sxaddpar,varhdr,'MPFILE',mpfile,' master prof file applied'
					sxaddpar,varhdr,'MPIMNO',mpimgno,' master prof image number'
					;
					; output variance image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_vcubep',/nodir)
					ecwi_write_image,var,varhdr,ofil,ppar
					;
					; update header
					sxaddpar,hdr,'COMMENT','  '+pre+' '+systime(0)
					sxaddpar,hdr,'PROFCOR','T',' prof corrected?'
					sxaddpar,hdr,'MPFILE',mpfile,' master prof file applied'
					sxaddpar,hdr,'MPIMNO',mpimgno,' master prof image number'
					;
					; write out final intensity image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_icubep',/nodir)
					ecwi_write_image,img,hdr,ofil,ppar
					;
					; check for nod-and-shuffle sky image
					sfil = repstr(obfil,'_icube','_scube')
					if file_test(sfil) then begin
						sky = mrdfits(sfil,0,skyhdr,/fscale,/silent)
						;
						; do correction
						for is=0,11 do for iy = 0, sz[2]-1 do $
							sky[*,is,iy] = sky[*,is,iy] / mprof[*,is]
						;
						; update header
						sxaddpar,skyhdr,'COMMENT','  '+pre+' '+systime(0)
						sxaddpar,skyhdr,'PROFCOR','T',' prof corrected?'
						sxaddpar,skyhdr,'MPFILE',mpfile,' master prof file applied'
						sxaddpar,skyhdr,'MPIMNO',mpimgno,' master prof image number'
						;
						; write out final intensity image
						ofil = ecwi_get_imname(ppar,imgnum[i],'_scubep',/nodir)
						ecwi_write_image,sky,hdr,ofil,ppar
					endif
					;
					; check for nod-and-shuffle obj image
					nfil = repstr(obfil,'_icube','_ocube')
					if file_test(nfil) then begin
						obj = mrdfits(nfil,0,objhdr,/fscale,/silent)
						;
						; do correction
						for is=0,11 do for iy = 0, sz[2]-1 do $
							obj[*,is,iy] = obj[*,is,iy] / mprof[*,is]
						;
						; update header
						sxaddpar,objhdr,'COMMENT','  '+pre+' '+systime(0)
						sxaddpar,objhdr,'PROFCOR','T',' prof corrected?'
						sxaddpar,objhdr,'MPFILE',mpfile,' master prof file applied'
						sxaddpar,objhdr,'MPIMNO',mpimgno,' master prof image number'
						;
						; write out final intensity image
						ofil = ecwi_get_imname(ppar,imgnum[i],'_ocubep',/nodir)
						ecwi_write_image,obj,hdr,ofil,ppar
					endif
					;
					; handle the case when no prof frames were taken
				endif else begin
					ecwi_print_info,ppar,pre,'cannot associate with any master prof: ' + $
						ecfg.obsfname,/warning
				endelse
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
			ecwi_print_info,ppar,pre,'input file not found: '+obfil,/warning
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
