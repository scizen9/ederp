;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_VERIFY_GEOM
;
; PURPOSE:
;	This function verifies the input ECWI_GEOM struct.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	Result = ECWI_VERIFY_GEOM(Egeom)
;
; INPUTS:
;	Egeom	- ECWI_GEOM struct
;
; RETURNS:
;	The status of the input ECWI_GEOM struct:
;	0	- verified without problems
;	1	- a malformed or uninitialized ECWI_GEOM struct was passed
;
; KEYWORDS:
;	INITIALIZED - set to check if ECWI_GEOM struct is initialized
;	SILENT	- set to silence output
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-SEP-15	Initial version
;-
function ecwi_verify_geom,egeom,initialized=initialized,silent=silent
	;
	; setup
	pre = 'ECWI_VERIFY_GEOM'
	;
	; check input
	stat = 0
	sz = size(egeom)
	if sz[0] ne 1 or sz[1] lt 1 or sz[2] ne 8 then begin
		if not keyword_set(silent) then $
			print,pre+': Error - malformed ECWI_GEOM struct'
		stat = 1
	endif else begin
		if keyword_set(initialized) then begin
			if egeom.initialized ne 1 then begin
				if not keyword_set(silent) then $
					print,pre+': Error - ECWI_GEOM struct not initialized, run ECWI_TRACE_CBARS and ECWI_EXTRACT_ARCS first'
				stat = 1
			endif
		endif
	endelse
	;
	return,stat
end
