;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_STAGE1
;
; PURPOSE:
;	This procedure takes the data through basic CCD reduction which
;	includes: bias and overscan removal and trimming, gain correction,
;	cosmic ray removal, mask generation and variance image generation.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_STAGE1, Pparfname, Linkfname
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
;	PROC_BIASNUMS - set to the corresponding master bias image numbers
;	NOTE: PROC_IMGNUMS and PROC_BIASNUMS must have the same number of items
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
;	of input files and their associated master bias files.  Each input
;	file is read in and the required master bias is generated and 
;	subtracted.  The overscan region for each calibration and object 
;	image is then analyzed and a row-by-row subtraction is performed 
;	to remove 1/f noise in the readout.  The images are trimmed and 
;	assembled into physical CCD-sized images.  Next, a gain correction 
;	for each amplifier is applied to convert each image into electrons.
;	The object images are then analyzed for cosmic rays and a mask image 
;	is generated indicating where the cosmic rays were removed.  Variance 
;	images for each object image are generated from the cleaned images 
;	which accounts for Poisson and CCD read noise.
;
; EXAMPLE:
;	Perform stage1 reductions on the images in 'night1' directory and put
;	results in 'night1/redux':
;
;	ECWI_PREP,'night1','night1/redux'
;	ECWI_STAGE1,'night1/redux/ecwi.ppar'
;
; TODO:
;	1. Defect correction step, right after CR removal (use same mask)
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-MAY-10	Initial version
;	2013-MAY-16	Added ECWI_LA_COSMIC call to clean image of CRs
;	2013-JUL-02	Handles case when no bias frames were taken
;			Made final output image *_int.fits for all input imgs
;	2013-JUL-09	Reject cosmic rays for continuum lamp obs
;	2013-JUL-16	Now uses ecwi_stage1_prep to do the bookkeeping
;	2013-AUG-09	Writes out sky image for nod-and-shuffle observations
;	2013-SEP-10	Changes cr sigclip for cflat images with nasmask
;	2014-APR-03	Uses master ppar and link files
;	2014-APR-06	Now makes mask and variance images for all types
;	2014-MAY-01	Handles aborted nod-and-shuffle observations
;	2014-SEP-29	Added infrastructure to handle selected processing
;-
pro ecwi_stage1,ppfname,linkfname,help=help,select=select, $
	proc_imgnums=proc_imgnums, proc_biasnums=proc_biasnums, $
	verbose=verbose, display=display
	;
	; setup
	pre = 'ECWI_STAGE1'
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
	; verify directories
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
		if n_elements(proc_biasnums) ne nproc then begin
			ecwi_print_info,ppar,pre,'Number of biases must equal number of images',/error
			return
		endif
		imgnum = proc_imgnums
		bnums = proc_biasnums
	;
	; if not, use link file
	endif else begin
		;
		; read link file
		ecwi_read_links,ppar,linkfname,imgnum,bias=bnums,count=nproc, $
			select=select
		if imgnum[0] lt 0 then begin
			ecwi_print_info,ppar,pre,'reading link file',/error
			return
		endif
	endelse
	;
	; log file
	lgfil = reddir + 'ecwi_stage1.log'
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
		printf,ll,'Processing images : ',imgnum
		printf,ll,'Using these biases: ',bnums
	endif else $
		printf,ll,'Master link file: '+linkfname
	printf,ll,'Min oscan pix: '+strtrim(string(ppar.minoscanpix),2)
	if ppar.crzap eq 0 then $
		printf,ll,'No cosmic ray rejection performed'
	if ppar.nassub eq 0 then $
		printf,ll,'No nod-and-shuffle sky subtraction performed'
	if ppar.saveintims eq 1 then $
		printf,ll,'Saving intermediate images'
	if ppar.includetest eq 1 then $
		printf,ll,'Including test images in processing'
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Display level     : ',ppar.display
	;
	; plot status
	doplots = (ppar.display ge 1)
	;
	; gather configuration data on each observation in rawdir
	ecwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; raw image to process
		obfil = ecwi_get_imname(ppar,imgnum[i],/raw,/exist)
		ecfg = ecwi_read_cfg(obfil)
		;
		; final reduced output file
		ofil = ecwi_get_imname(ppar,imgnum[i],'_int',/reduced)
		;
		; trim image type
		ecfg.imgtype = strtrim(ecfg.imgtype,2)
		;
		; check if file exists or if we want to overwrite it
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
			; get ccd geometry
			ecwi_map_ccd,hdr,asec,bsec,csec,tsec,namps=namps,trimmed_size=tsz,verbose=ppar.verbose
			;
			; check amps
			if namps le 0 then begin
				ecwi_print_info,ppar,pre,'no amps found for image, check NVIDINP hdr keyword',/error
				free_lun,ll
				return
			endif
			;
			; log
			ecwi_print_info,ppar,pre,'number of amplifiers',namps
			;
			; initialize to default value
			mbias_rn = fltarr(4) + ppar.readnoise
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; BEGIN STAGE 1-A: BIAS SUBTRACTION
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			; set default values
			mbias = 0.
			avrn = ppar.readnoise
			;
			; do we have a bias link?
			do_bias = (1 eq 0)	; assume no to begin with
			if bnums[i] ge 0 then begin
				;
				; master bias file name
				;mbfile = cdir + 'mbias_' + strn(bnums[i]) + '.fits'
				mbfile = cdir + 'mbias_' + string(bnums[i],'(i0'+strn(ppar.fdigits)+')') + '.fits'
				;
				; master bias image ppar filename
				mbppfn = strmid(mbfile,0,strpos(mbfile,'.fits')) + '.ppar'
				;
				; check access
				if file_test(mbppfn) then begin
					do_bias = (1 eq 1)
					;
					; log that we got it
					ecwi_print_info,ppar,pre,'bias file = '+mbfile
				endif else begin
					;
					; log that we haven't got it
					ecwi_print_info,ppar,pre,'bias file not found: '+mbfile,/error
				endelse
			endif
			;
			; let's read in or create master bias
			if do_bias then begin
				;
				; build master bias if necessary
				if not file_test(mbfile) then begin
					;
					; build master bias
					bpar = ecwi_read_ppar(mbppfn)
					bpar.loglun  = ppar.loglun
					bpar.verbose = ppar.verbose
					bpar.display = ppar.display
					ecwi_make_bias,bpar
				endif
				;
				; read in master bias
				mbias = mrdfits(mbfile,0,mbhdr,/fscale,/silent)
				;
				; loop over master bias amps and get read noise value(s)
				nba = sxpar(mbhdr,'NVIDINP')
				avrn = 0.
				for ia=0,nba-1 do begin
					mbias_rn[ia] = sxpar(mbhdr,'BIASRN'+strn(ia+1))
					sxaddpar,hdr,'BIASRN'+strn(ia+1),mbias_rn[ia],' amp'+strn(ia+1)+' RN in e- from bias'
					avrn = avrn + mbias_rn[ia]
				endfor
				avrn = avrn / float(nba)
				;
				; compare number of amps
				if nba ne namps then begin
					ecwi_print_info,ppar,pre,'amp number mis-match (bais vs. obs)',nba,namps,/warning
					;
					; handle mis-match
					case nba of
						1: mbias_rn[1:3] = mbias_rn[0]		; set all to single-amp value
						2: begin
							mbias_rn[2] = mbias_rn[0]	; set ccd halves to be the same
							mbias_rn[3] = mbias_rn[1]
						end
						else:					; all other cases are OK as is
					endcase
				endif
				;
				; update header
				sxaddpar,hdr,'BIASSUB','T',' bias subtracted?'
				sxaddpar,hdr,'MBFILE',mbfile,' master bias file subtracted'
			;
			; handle the case when no bias frames were taken
			endif else begin
				ecwi_print_info,ppar,pre,'cannot associate with any master bias: '+ecfg.obsfname,/warning
				ecwi_print_info,ppar,pre,'using default readnoise',ppar.readnoise,/warning
				sxaddpar,hdr,'BIASSUB','F',' bias subtracted?'
			endelse
			;
			; subtract bias
			img = img - mbias
			;
			; output file, if requested and if bias subtracted
			if ppar.saveintims eq 1 and do_bias then begin
				ofil = ecwi_get_imname(ppar,imgnum[i],'_b',/nodir)
				ecwi_write_image,img,hdr,ofil,ppar
			endif
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; END   STAGE 1-A: BIAS SUBTRACTION
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; BEGIN STAGE 1-B: OVERSCAN SUBTRACTION
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			; number of overscan pixels in each row
			oscan_pix	= bsec[0,0,1] - bsec[0,0,0]
			;
			; do we have enough overscan to get good statistics?
			if oscan_pix ge ppar.minoscanpix and ecfg.gain1 eq 2. then begin
				;
				; loop over amps
				for ia = 0, namps-1 do begin
					;
					; overscan x range - buffer avoids edge effects
					osx0	= bsec[ia,0,0] + ppar.oscanbuf
					osx1	= bsec[ia,0,1] - ppar.oscanbuf
					;
					; range in x to subtract overscan from
					asx0	= asec[ia,0,0]
					asx1	= asec[ia,0,1]
					;
					; row range (y)
					osy0	= bsec[ia,1,0]
					osy1	= bsec[ia,1,1]
					;
					; collapse each row
					osvec = median(img[osx0:osx1,osy0:osy1],dim=1)
					xx = findgen(n_elements(osvec)) + osy0
					;
					; fit overscan vector
					res = polyfit(xx,osvec,7,osfit)
					;
					; plot if display set
					if doplots then begin
						resid = osvec - osfit
						mo = moment(resid)
						deepcolor
						!p.background=colordex('white')
						!p.color=colordex('black')
						plot,xx,osvec,/xs,psym=1,xtitle='ROW',ytitle='<DN>', $
							title='Amp/Namps: '+strn(ia+1)+'/'+strn(namps)+ $
							', Oscan Cols: '+strn(osx0)+' - '+strn(osx1)+ $
							', Image: '+strn(imgnum[i]), $
							charth=2,charsi=1.5,xthi=2,ythi=2,ystyle=1
						oplot,xx,osfit,thick=2,color=colordex('green')
						ecwi_legend,['Resid RMS: '+string(sqrt(mo[1]),form='(f5.1)')+$
							' DN'],box=0,charthi=2,charsi=1.5,/right,/bottom
					endif
					;
					; loop over rows
					for iy = osy0,osy1 do begin
						;
						; get oscan fit value at row iy
						ip = where(xx eq iy, nip)
						if nip eq 1 then begin
							osval = osfit[ip[0]]
						endif else begin
							ecwi_print_info,ppar,pre,'no corresponding overscan pixel for row',iy,/warning
							osval = 0.
						endelse
						;
						; apply over entire amp range
						img[asx0:asx1,iy] = img[asx0:asx1,iy] - osval
					endfor
					;
					; log
					ecwi_print_info,ppar,pre,'overscan '+strtrim(string(ia+1),2)+'/'+ $
						strtrim(string(namps),2)+' (x0,x1,y0,y1): '+ $
						    strtrim(string(osx0),2)+','+strtrim(string(osx1),2)+ $
						','+strtrim(string(osy0),2)+','+strtrim(string(osy1),2)
					;
					; make interactive if display greater than 1
					if doplots and ppar.display ge 2 then begin
						q = ''
						read,'Next? (Q-quit plotting, <cr>-next): ',q
						if strupcase(strmid(q,0,1)) eq 'Q' then doplots = 0
					endif
				endfor	; loop over amps
				;
				; update header
				sxaddpar,hdr,'OSCANSUB','T',' overscan subtracted?'
				;
				; output file, if requested
				if ppar.saveintims eq 1 then begin
					ofil = ecwi_get_imname(ppar,imgnum[i],'_o',/nodir)
					ecwi_write_image,img,hdr,ofil,ppar
				endif
			endif else begin	; no overscan to subtract
				ecwi_print_info,ppar,pre,'not subtracting overscan for ph-counted imgs',/warning
				sxaddpar,hdr,'OSCANSUB','F',' overscan subtracted?'
			endelse
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; END   STAGE 1-B: OVERSCAN SUBTRACTION
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; BEGIN STAGE 1-C: IMAGE TRIMMING
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			; create trimmed array
			imgo = fltarr(tsz[0],tsz[1])
			;
			; loop over amps
			for ia = 0, namps-1 do begin
				;
				; input ranges
				xi0 = csec[ia,0,0]
				xi1 = csec[ia,0,1]
				yi0 = csec[ia,1,0]
				yi1 = csec[ia,1,1]
				;
				; output ranges
				xo0 = tsec[ia,0,0]
				xo1 = tsec[ia,0,1]
				yo0 = tsec[ia,1,0]
				yo1 = tsec[ia,1,1]
				;
				; copy into trimmed image
				imgo[xo0:xo1,yo0:yo1] = img[xi0:xi1,yi0:yi1]
				;
				; update header using 1-bias indices
				sec = '['+strn(yo0+1)+':'+strn(yo1+1)+',' + $
					  strn(xo0+1)+':'+strn(xo1+1)+']'
				sxaddpar,hdr,'ATSEC'+strn(ia+1),sec,' trimmed section for amp'+strn(ia+1), $
					after='ASEC'+strn(ia+1)
				;
				; remove old sections, no longer valid
				sxdelpar,hdr,'ASEC'+strn(ia+1)
				sxdelpar,hdr,'BSEC'+strn(ia+1)
				sxdelpar,hdr,'CSEC'+strn(ia+1)
				sxdelpar,hdr,'DSEC'+strn(ia+1)
				sxdelpar,hdr,'TSEC'+strn(ia+1)
			endfor	; loop over amps
			;
			; transpose image
			;
			; store trimmed image
			img = imgo
			sz = size(img,/dimension)
			;
			; update header
			sxaddpar,hdr,'IMGTRIM','T',' image trimmed?'
			sxdelpar,hdr,'ROISEC'	; no longer valid
			;
			; log
			ecwi_print_info,ppar,pre,'trimmed image size: '+strtrim(string(sz[0]),2)+'x'+strtrim(string(sz[1]),2)
			;
			; output file, if requested
			if ppar.saveintims eq 1 then begin
				ofil = ecwi_get_imname(ppar,imgnum[i],'_t',/nodir)
				ecwi_write_image,img,hdr,ofil,ppar
			endif
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; END   STAGE 1-C: IMAGE TRIMMING
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; BEGIN STAGE 1-D: GAIN CORRECTION
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			; loop over amps
			gainstr = ''
			for ia = 0, namps-1 do begin
				;
				; get gain
				gain = sxpar(hdr,'GAIN'+strn(ia+1))
				gainstr = gainstr + string(gain,form='(f6.3)')+' '
				;
				; output ranges
				xo0 = tsec[ia,0,0]
				xo1 = tsec[ia,0,1]
				yo0 = tsec[ia,1,0]
				yo1 = tsec[ia,1,1]
				;
				; gain correct data
				img[xo0:xo1,yo0:yo1] = img[xo0:xo1,yo0:yo1] * gain
			endfor
			;
			; update header
			sxaddpar,hdr,'COMMENT','  '+ecwi_drp_version()
			sxaddpar,hdr,'COMMENT','  '+pre+' '+systime(0)
			sxaddpar,hdr,'GAINCOR','T',' gain corrected?'
			sxaddpar,hdr,'BUNIT','electrons',' brightness units'
			;
			; log
			ecwi_print_info,ppar,pre,'amplifier gains (e/DN)',gainstr
			;
			; output gain-corrected image
			if ppar.saveintims eq 1 then begin
				ofil = ecwi_get_imname(ppar,imgnum[i],'_e',/nodir)
				ecwi_write_image,img,hdr,ofil,ppar
			endif
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; END   STAGE 1-D: GAIN CORRECTION
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; BEGIN STAGE 1-E: COSMIC RAY REJECTION AND MASKING
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			; ONLY perform next step on OBJECT, DARK, and CFLAT images (and if requested)
			if (strmatch(ecfg.imgtype,'object') eq 1 or $
			    strmatch(ecfg.imgtype,'dark') eq 1 or $
			    strmatch(ecfg.imgtype,'cflat') eq 1) and ppar.crzap eq 1 then begin
			    	;
			    	; default sigclip
			    	sigclip = 4.5
				;
				; test for cflat and nasmask
				if strmatch(ecfg.imgtype,'cflat') eq 1 then begin
					if ecfg.nasmask eq 1 then $
						sigclip = 10.0 $
					else	sigclip = 7.0
				endif
				;
				; test for short exposures
				if strmatch(ecfg.imgtype,'object') eq 1 then begin
					if ecfg.exptime lt 300. then $
						sigclip = 10. $
					else	sigclip = 4.5
				endif
				;
				; call ecwi_la_cosmic
				ecwi_la_cosmic,img,ppar,crmsk,readn=avrn,gain=1.,objlim=4.,sigclip=sigclip, $
					ntcosmicray=ncrs
				;
				; update main header
				sxaddpar,hdr,'CRCLEAN','T',' cleaned cosmic rays?'
				sxaddpar,hdr,'NCRCLEAN',ncrs,' number of cosmic rays cleaned'
				sxaddpar,hdr,'COMMENT','  ECWI_LA_COSMIC '+systime(0)
				;
				; write out cleaned object image
				if ppar.saveintims eq 1 then begin
					ofil = ecwi_get_imname(ppar,imgnum[i],'_cr',/nodir)
					ecwi_write_image,img,hdr,ofil,ppar
				endif
				;
				; update CR mask header
				mskhdr = hdr
				sxdelpar,mskhdr,'BUNIT'
				sxaddpar,mskhdr,'BSCALE',1.
				sxaddpar,mskhdr,'BZERO',0
				sxaddpar,mskhdr,'MASKIMG','T',' mask image?'
				sxaddpar,mskhdr,'CRCLEAN','T',' cleaned cosmic rays?'
				sxaddpar,mskhdr,'NCRCLEAN',ncrs,' number of cosmic rays cleaned'
				;
				; write out CR mask image
				if ppar.saveintims eq 1 then begin
					ofil = ecwi_get_imname(ppar,imgnum[i],'_crmsk',/nodir)
					ecwi_write_image,crmsk,mskhdr,ofil,ppar
				endif
			endif else begin
				if ppar.crzap ne 1 then $
					ecwi_print_info,ppar,pre,'cosmic ray cleaning skipped',/warning
				sxaddpar,hdr,'CRCLEAN','F',' cleaned cosmic rays?'
				crmsk = 0.
			endelse
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; END   STAGE 1-E: COSMIC RAY REJECTION AND MASKING
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; BEGIN STAGE 1-F: IMAGE DEFECT CORRECTION AND MASKING
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			; create mask
			msk = bytarr(sz)
			;
			; be sure that output image scaling will work
			msk[0] = 1b
			;
			; get defect list
			nbpix = 0
			bpx = [0]
			bpy = [0]
			;
			; fix bad pixels
			if nbpix gt 0 then begin
				for ib=0,nbpix do begin
					print,ib
					msk[bpx[ib],bpy[ib]] = 2b
				endfor
			endif
			;
			; does cosmic ray mask image and header already exist?
			if n_elements(crmsk) gt 1 then begin
				cpix = where(crmsk eq 1, ncpix)
				if ncpix gt 0 then msk[cpix] = msk[cpix] + 1b
			;
			; if not, create header
			endif else begin
				mskhdr = hdr
				sxdelpar,mskhdr,'BUNIT'
				sxaddpar,mskhdr,'BSCALE',1.
				sxaddpar,mskhdr,'BZERO',0
				sxaddpar,mskhdr,'MASKIMG','T',' mask image?'
			endelse
			;
			; update headers
			; image
			sxaddpar,hdr,'BPCLEAN','T',' cleaned bad pixels?'
			sxaddpar,hdr,'NBPCLEAN',nbpix,' number of bad pixels cleaned'
			; mask
			sxaddpar,mskhdr,'BPCLEAN','T',' cleaned bad pixels?'
			sxaddpar,mskhdr,'NBPCLEAN',nbpix,' number of bad pixels cleaned'
			;
			; log
			ecwi_print_info,ppar,pre,'number of bad pixels = '+strtrim(string(nbpix),2)
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; END   STAGE 1-F: IMAGE DEFECT CORRECTION AND MASKING
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; BEGIN STAGE 1-G: CREATE VARIANCE IMAGE
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			; Poisson variance is electrons per pixel
			var = img
			varhdr = hdr
			;
			; loop over amps
			for ia = 0, namps-1 do begin
				;
				; output ranges
				xo0 = tsec[ia,0,0]
				xo1 = tsec[ia,0,1]
				yo0 = tsec[ia,1,0]
				yo1 = tsec[ia,1,1]
				;
				; variance is electrons + RN^2
				var[xo0:xo1,yo0:yo1] = (img[xo0:xo1,yo0:yo1]>0) + mbias_rn[ia]^2
			endfor
			avvar = avg(var)
			;
			; update header
			sxaddpar,varhdr,'VARIMG','T',' variance image?'
			sxaddpar,varhdr,'BUNIT','variance',' brightness units'
			;
			; log
			ecwi_print_info,ppar,pre,'average variance = '+strtrim(string(avvar),2)
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; END   STAGE 1-G: CREATE VARIANCE IMAGE
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; BEGIN STAGE 1-H: NOD-AND-SHUFFLE SUBTRACTION
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			; ONLY perform next step on OBJECT images
			if ppar.nassub eq 1 and strmatch(ecfg.imgtype,'object') eq 1 and $
				ecfg.nasmask eq 1 and ecfg.shuffmod eq 1 then begin
				;
				; check panel limits
				if ecfg.nsskyr0 le 0 then $
					ecwi_print_info,ppar,pre,'are nod-and-shuffle panel limits 1-biased?',/warning
				;
				; get panel limits, convert to 0-bias
				skyrow0 = (ecfg.nsskyr0 - 1) > 0
				skyrow1 = (ecfg.nsskyr1 - 1) > 0
				objrow0 = (ecfg.nsobjr0 - 1) > 0
				objrow1 = (ecfg.nsobjr1 - 1) > 0
				;
				; check limits
				if (skyrow1-skyrow0) eq (objrow1-objrow0) then begin
					;
					; create intermediate images
					sky = img
					obj = img
					;
					; sky in the bottom third (normal nod-and-shuffle config)
					if skyrow0 lt 10 then begin
						;
						; get variance and mask images
						skyvar = var
						skymsk = msk
						;
						; move sky to object position
						sky[*,objrow0:objrow1] = img[*,skyrow0:skyrow1]
						skyvar[*,objrow0:objrow1] = var[*,skyrow0:skyrow1]
						skymsk[*,objrow0:objrow1] = msk[*,skyrow0:skyrow1]
						;
						; do subtraction
						img = img - sky
						var = var + skyvar
						msk = msk + skymsk
						;
						; clean images
						img[*,skyrow0:skyrow1] = 0.
						img[*,objrow1+1:*] = 0.
						var[*,skyrow0:skyrow1] = 0.
						var[*,objrow1+1:*] = 0.
						msk[*,skyrow0:skyrow1] = 0b
						msk[*,objrow1+1:*] = 0b
						sky[*,skyrow0:skyrow1] = 0.
						sky[*,objrow1+1:*] = 0.
						obj[*,skyrow0:skyrow1] = 0.
						obj[*,objrow1+1:*] = 0.
					;
					; sky is in middle third (aborted nod-and-shuffle during sky obs)
					endif else begin
						;
						; log non-standard reduction
						ecwi_print_info,ppar,pre,'non-standard nod-and-shuffle configuration: sky in center third',/warning
						;
						; get variance and mask images
						objvar = var
						objmsk = msk
						;
						; move obj to sky position
						obj[*,skyrow0:skyrow1] = img[*,objrow0:objrow1]
						objvar[*,skyrow0:skyrow1] = var[*,objrow0:objrow1]
						objmsk[*,skyrow0:skyrow1] = msk[*,objrow0:objrow1]
						;
						; do subtraction
						img = obj - img
						var = var + objvar
						msk = msk + objmsk
						;
						; clean images
						img[*,objrow0:objrow1] = 0.
						img[*,0:skyrow0-1] = 0.
						var[*,objrow0:objrow1] = 0.
						var[*,0:skyrow0-1] = 0.
						msk[*,objrow0:objrow1] = 0b
						msk[*,0:skyrow0-1] = 0b
						sky[*,objrow0:objrow1] = 0.
						sky[*,0:skyrow0-1] = 0.
						obj[*,objrow0:objrow1] = 0.
						obj[*,0:skyrow0-1] = 0.
					endelse
					;
					; update headers
					skyhdr = hdr
					objhdr = hdr
					sxaddpar,objhdr,'NASSUB','F',' Nod-and-shuffle subtraction done?'
					sxaddpar,skyhdr,'NASSUB','F',' Nod-and-shuffle subtraction done?'
					sxaddpar,skyhdr,'SKYOBS','T',' Sky observation?'
					sxaddpar,hdr,'NASSUB','T',' Nod-and-shuffle subtraction done?'
					sxaddpar,varhdr,'NASSUB','T',' Nod-and-shuffle subtraction done?'
					sxaddpar,mskhdr,'NASSUB','T',' Nod-and-shuffle subtraction done?'
					;
					; log
					ecwi_print_info,ppar,pre,'nod-and-shuffle subtracted, rows (sky0,1, obj0,1)', $
						skyrow0,skyrow1,objrow0,objrow1,format='(a,4i6)'
					;
					; write out sky image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_sky',/nodir)
					ecwi_write_image,sky,skyhdr,ofil,ppar
					;
					; write out obj image
					ofil = ecwi_get_imname(ppar,imgnum[i],'_obj',/nodir)
					ecwi_write_image,obj,objhdr,ofil,ppar
				endif else $
					ecwi_print_info,ppar,pre, $
						'nod-and-shuffle sky/obj row mismatch (no subtraction done)',/warning
				;
				; nod-and-shuffle subtraction requested for object
			endif else begin
				;
				; nod-and-shuffle _NOT_ requested for object
				if strmatch(ecfg.imgtype,'object') eq 1 and $
					ecfg.nasmask eq 1 and ecfg.shuffmod eq 1 then $
						ecwi_print_info,ppar,pre, $
						'nod-and-shuffle sky subtraction skipped for nod-and-shuffle image', $
						/warning
			endelse
			;
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			; END   STAGE 1-H: NOD-AND-SHUFFLE SUBTRACTION
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			;
			; write out mask image
			if ecfg.juliandate lt 2457523.0 then $
				msk = rotate(msk,1) $
			else	msk = rotate(msk,6)
			ofil = ecwi_get_imname(ppar,imgnum[i],'_msk',/nodir)
			ecwi_write_image,msk,mskhdr,ofil,ppar
			;
			; output variance image
			if ecfg.juliandate lt 2457523.0 then $
				var = rotate(var,1) $
			else	var = rotate(var,6)
			ofil = ecwi_get_imname(ppar,imgnum[i],'_var',/nodir)
			ecwi_write_image,var,varhdr,ofil,ppar
			;
			; write out final intensity image
			if ecfg.juliandate lt 2457523.0 then $
				img = rotate(img,1) $
			else	img = rotate(img,6)
			ofil = ecwi_get_imname(ppar,imgnum[i],'_int',/nodir)
			ecwi_write_image,img,hdr,ofil,ppar
		;
		; end check if output file exists already
		endif else begin
			ecwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+ecfg.imgtype,/warning
			if ppar.clobber eq 0 and file_test(ofil) then $
				ecwi_print_info,ppar,pre,'processed file exists already',/warning
		endelse
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
