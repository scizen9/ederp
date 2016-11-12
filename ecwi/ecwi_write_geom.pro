;
; Copyright (c) 2014, California Institute of Technology. All rights reserved.
;+
; NAME:
;	ECWI_WRITE_GEOM
;
; PURPOSE:
;	Writes out the ECWI_GEOM struct as an IDL save file
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_WRITE_GEOM,Ppar,Egeom
;
; INPUTS:
;	Egeom	- ECWI_GEOM struct
;	Ppar	- ECWI_PPAR pipeline parameter struct
;
; INPUT KEYWORDS:
;	TEST	- only write out if egeom.status=0 (good fit)
;
; OUTPUTS:
;	None.
;
; PROCEDURE:
;	Uses the tag egeom.geomfile to write out the struct as an IDL
;	save file.  Checks if ppar.clobber is set and takes appropriate
;	action.
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2014-SEP-11	Initial Revision
;-
;
pro ecwi_write_geom,ppar,egeom, test=test
;
; startup
pre = 'ECWI_WRITE_GEOM'
q = ''
;
; check inputs
if n_params(0) lt 1 or keyword_set(help) then begin
	print,pre+': Info - Usage: '+pre+', Ppar, Egeom'
	return
endif
;
; Check structs
if ecwi_verify_geom(egeom,/init) ne 0 then return
if ecwi_verify_ppar(ppar,/init) ne 0 then return
;
; check fit status
if keyword_set(test) and egeom.status ne 0 then begin
	ecwi_print_info,ppar,pre,'Egeom fit no good, nothing written.',/error
	return
endif
;
; write it out
; check if it exists already
if file_test(egeom.geomfile) then begin
	;
	; clobber it, if requested
    	if ppar.clobber eq 1 then begin
		file_delete,egeom.geomfile,verbose=ppar.verbose
		ecwi_print_info,ppar,pre,'deleted existing geom file', $
			egeom.geomfile,format='(a,a)'
	endif else begin
		ecwi_print_info,ppar,pre, $
			'existing geom file undisturbed', $
			egeom.geomfile,format='(a,a)'
		return
	endelse
endif
;
; write it out if we get here
save,egeom,filename=egeom.geomfile
ecwi_print_info,ppar,pre,'wrote geom file',egeom.geomfile,format='(a,a)'
;
return
end
