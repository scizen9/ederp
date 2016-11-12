;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_ASSOCIATE
;
; PURPOSE:
;	This function returns the indices of the ECWI_CFG array that
;	is closest in time to the target ECWI_CFG scalar input.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	Result = ECWI_ASSOCIATE( ECFG, TCFG )
;
; INPUTS:
;	Ecfg	- array of struct ECWI_CFG for a given group
;	Tcfg	- target scalar struct ECWI_CFG to match
;	Ppar	- pipeline parameters ECWI_PPAR struct
;
; Returns:
;	Index of the Ecfg entry that is closest in time to the target Tcfg
;
; INPUT KEYWORDS:
;	AFTER	- match the closest in time after epoch of target
;	BEFORE	- match the closest in time before epoch of target
;
; OUTPUT KEYWORD:
;	COUNT	- set to get extra screen output
;
; SIDE EFFECTS:
;	None.
;
; PROCEDURE:
;	Compares target Julian date given by Tcfg to Julian dates for
;	group contained in Ecfg and finds the entry with the smallest
;	time offset compared to the target.
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-MAY-08	Initial version
;	2013-OCT-31	Now returns matched ECWI_CFG struct
;	2013-NOV-01	Added AFTER/BEFORE keywords
;-
function ecwi_associate, ecfg, tcfg, ppar, $
	after=after, before=before, count=count
	;
	; setup
	pre = 'ECWI_ASSOCIATE'
	count = 0
	;
	; check inputs
	if ecwi_verify_ppar(ppar,/init,/silent) ne 0 then begin
		ecwi_print_info,ppar,pre,'Ppar - malformed ECWI_PPAR struct',/error
		match = -1
	endif
	if ecwi_verify_cfg(ecfg,/init,/silent) ne 0 then begin
		ecwi_print_info,ppar,pre,'Search - malformed ECWI_CFG struct array',/error
		match = -1
	endif
	if ecwi_verify_cfg(tcfg,/init,/silent) ne 0 then begin
		ecwi_print_info,ppar,pre,'Target - malformed ECWI_CFG struct array',/error
		match = -1
	endif
	if tcfg.juliandate le 0. then begin
		ecwi_print_info,ppar,pre,'target date not set',/error
		match = -1
	endif
	if total(ecfg.juliandate) le 0. then begin
		ecwi_print_info,ppar,pre,'group dates not set',/error
		match = -1
	endif
	;
	; check after match
	if keyword_set(after) then begin
		offs = ecfg.juliandate - tcfg.juliandate
		a = where(offs ge 0., na)
		if na gt 0 then begin
			offs = offs[a]
			match = (where(offs eq min(offs)))[0]
		endif else begin
			ecwi_print_info,ppar,pre,'no after match',/error
			match = -1
		endelse
	;
	; check before match
	endif else if keyword_set(before) then begin
		offs = tcfg.juliandate - ecfg.juliandate
		b = where(offs ge 0., nb)
		if nb gt 0 then begin
			offs = offs[b]
			match = (where(offs eq min(offs)))[0]
		endif else begin
			ecwi_print_info,ppar,pre,'no before match',/error
			match = -1
		endelse
	;
	; get offsets
	endif else begin
		offs = abs(ecfg.juliandate - tcfg.juliandate)
		match = (where(offs eq min(offs)))[0]
	endelse
	;
	if match[0] ge 0 then begin
		count = 1
		return,ecfg[match]
	endif else return,match
end
