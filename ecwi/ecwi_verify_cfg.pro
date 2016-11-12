;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_VERIFY_CFG
;
; PURPOSE:
;	This function verifies the input ECWI_CFG struct.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	Result = ECWI_VERIFY_CFG(Ecfg)
;
; INPUTS:
;	Ecfg	- array of struct ECWI_CFG
;
; RETURNS:
;	The status of the input ECWI_CFG struct:
;	0	- verified without problems
;	1	- a malformed ECWI_CFG struct was passed
;
; KEYWORDS:
;	INITIALIZED - set to check if ECWI_CFG is initialized
;	SILENT	- set to silence output
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-JUL-08	Initial version
;	2013-SEP-14	Added initialized keyword
;-
function ecwi_verify_cfg,ecfg,initialized=initialized,silent=silent
	;
	; setup
	pre = 'ECWI_VERIFY_CFG'
	;
	; check input
	stat = 0
	sz = size(ecfg)
	if sz[0] ne 1 or sz[1] lt 1 or sz[2] ne 8 then begin
		if not keyword_set(silent) then $
			print,pre+': Error - malformed ECWI_CFG struct array'
		stat = 1
	endif else begin
		if keyword_set(initialized) then begin
			test = n_elements(ecfg)
			if total(ecfg.initialized) ne test then begin
				print,pre+': Error - ECWI_CFG struct not initialized'
				stat = 1
			endif
		endif
	endelse
	;
	return,stat
end
