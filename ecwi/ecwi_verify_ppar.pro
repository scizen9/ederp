;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_VERIFY_PPAR
;
; PURPOSE:
;	This function verifies the input ECWI_PPAR struct.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	Result = ECWI_VERIFY_PPAR(Ppar)
;
; INPUTS:
;	Ppar	- array of struct ECWI_PPAR
;
; RETURNS:
;	The status of the input ECWI_PPAR struct:
;	0	- verified without problems
;	1	- a malformed or uninitialized ECWI_PPAR struct was passed
;
; KEYWORDS:
;	INITIALIZED - set to check if ECWI_PPAR struct is initialized
;	SILENT	- set to silence output
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-SEP-13	Initial version
;	2013-SEP-14	Added initialized keyword
;-
function ecwi_verify_ppar,ppar,initialized=initialized,silent=silent
	;
	; setup
	pre = 'ECWI_VERIFY_PPAR'
	;
	; check input
	stat = 0
	sz = size(ppar)
	if sz[0] ne 1 or sz[1] lt 1 or sz[2] ne 8 then begin
		if not keyword_set(silent) then $
			print,pre+': Error - malformed ECWI_PPAR struct array'
		stat = 1
	endif else begin
		if keyword_set(initialized) then begin
			if ppar.initialized ne 1 then begin
				print,pre+': Error - ECWI_PPAR struct not initialized'
				stat = 1
			endif
		endif
	endelse
	;
	return,stat
end
