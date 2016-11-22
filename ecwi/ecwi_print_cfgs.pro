;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_PRINT_CFGS
;
; PURPOSE:
;	This function prints a summary of the configurations passed, one
;	line per image.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_PRINT_CFGS,Ecfg
;
; INPUTS:
;	Ecfg	- An array of struct ECWI_CFG.
;
; OUTPUTS:
;	imsum	- image summary (string)
;
; KEYWORDS:
;	header	- set to print headings for the columns
;	silent	- just return string, do not print
;	outfile	- filename to print to
;
; PROCEDURE:
;	Prints a summary allowing comparison of configurations of each image.
;
; EXAMPLE:
;	Read in the stage one processed image data headers in directory 
;	'redux' and return an array of struct ECWI_CFG.  Find all the
;	continuum flats and print their configuration summary.
;
;	KCFG = ECWI_PRINT_CFGS('redux',filespec='*_int.fits')
;	ECWI_PRINT_CFG, KCFG
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-JUL-08	Initial version
;	2013-NOV-13	Added outfile keyword
;-
pro ecwi_print_cfgs,ecfg,imsum,header=header,silent=silent,outfile=outfile
	;
	; setup
	pre = 'ECWI_PRINT_CFGS'
	imsum = ''
	;
	; check inputs
	if ecwi_verify_cfg(ecfg) ne 0 then return
	;
	; outfile?
	if keyword_set(outfile) then begin
		filestamp,outfile,/arch
		openw,ol,outfile,/get_lun
		printf,ol,'# '+pre+'  '+systime(0)
		printf,ol,'# SSM = Sky, Shuffle, Mask: 0 - no, 1 - yes'
		printf,ol,'#  #/   N Bin AMPS SSM GRAT FILT   FM4pos    GRpos   CAMpos   FOCpos   Cwave JDobs         Expt Type       Imno   RA          Dec             PA    Object'
	endif
	;
	; header?
	if keyword_set(header) and not keyword_set(silent) then begin
		print,' SSM = Sky, Shuffle, Mask: 0 - no, 1 - yes'
		print,'   #/   N Bin AMPS SSM GRAT FILT   FM4pos    GRpos   CAMpos   FOCpos   Cwave JDobs         Expt Type       Imno   RA          Dec             PA    Object'
	endif
	;
	; current date
	cdate = 0.d0
	;
	; loop over elements
	n = n_elements(ecfg)
	for i=0,n-1l do begin
		;
		; prepare summary
		imsum = string(i+1,'/',n,ecfg[i].xbinsize,ecfg[i].ybinsize, $
			strtrim(ecfg[i].ampmode,2),ecfg[i].skyobs, $
			ecfg[i].shuffmod,ecfg[i].nasmask, $
			strtrim(ecfg[i].gratid,2),strtrim(ecfg[i].filter,2), $
			ecfg[i].fm4pos,ecfg[i].gratpos,ecfg[i].campos, $
			ecfg[i].focpos,ecfg[i].cwave,ecfg[i].juliandate, $
			ecfg[i].exptime,strtrim(ecfg[i].imgtype,2), $
			ecfg[i].imgnum,ecfg[i].ra,ecfg[i].dec,ecfg[i].rotpa, $
			format='(i4,a1,i4,2i2,1x,a-5,3i1,1x,a-4,1x,a-4,4i9,f8.1,f12.3,f7.1,1x,a-8,i7,2f13.8,2x,f7.2)')
		;
		; add object info
		if strpos(ecfg[i].imgtype,'object') ge 0 then begin
			imsum = imsum + string(strtrim(ecfg[i].object,2),form='(2x,a)')
		endif
		if not keyword_set(silent) then print,imsum
		if keyword_set(outfile) then begin
			if i gt 0 then $
				deljd = ecfg[i].juliandate - ecfg[i-1].juliandate $
			else	deljd = 1.0
			if deljd gt 0.25 and ecfg[i].juliandate-cdate gt 0.75 then begin
				cdate = ecfg[i].juliandate
				caldat,long(cdate),month,day,year
				printf,ol,'# Run: ',year-2000.,month,day, $
					format='(a,i02,i02,i02)'
			endif
			printf,ol,imsum
		endif
	endfor
	if keyword_set(outfile) then free_lun,ol
	;
	return
end
