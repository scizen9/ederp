;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_PARSE_DATES
;
; PURPOSE:
;	This function reads the array of header date values and returns
;	an array of julian dates.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	Result = ECWI_PARSE_DATES( HDR_DATES )
;
; INPUTS:
;	hdr_dates - a string array of dates of form YYYY-MM-DDTHH:MM:SS.SSS
;
; KEYWORDS:
;	VERBOSE - set this to get extra screen output
;
; RETURNS:
;	a double array of julian dates corresponding to the input dates.
;
; PROCEDURE:
;	Parses each date and derives the julian date.
;
; EXAMPLE:
;
;	read one header and get it's corresponding unix time:
;	hdr=headfits('image1234.fits')
;	date = sxpar(hdr,'DATE')
;	jd = ecwi_parse_dates(date)
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-MAY-02	Initial version
;-
function ecwi_parse_dates,hdr_dates,verbose=verbose
;
; initialize
	pre = 'ECWI_PARSE_DATES'
;
; set up output array
	nd = n_elements(hdr_dates)
	jds = dblarr(nd)
;
; loop over elements
	for i=0,nd-1 do begin
		;
		; parse each element
		it = hdr_dates[i]
		yr = fix(gettok(it,'-'))
		mo = fix(gettok(it,'-'))
		dy = fix(gettok(it,'T'))
		hr = fix(gettok(it,':'))
		mi = fix(gettok(it,':'))
		se = float(it)
		;
		; convert to julian date
		if yr gt 0 then $
			jds[i] = julday(mo, dy, yr, hr, mi, se) $
		else	jds[i] = -1.d0
	endfor
	;
	return,jds
end
