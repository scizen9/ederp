;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_SOLVE_GEOM
;
; PURPOSE:
;	Solve the wavelength solutions for each arc spectrum
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_SOLVE_GEOM,Spec, Egeom, Ppar
;
; INPUTS:
;	Spec	- a array of arc spectra produced by ECWI_EXTRACT_ARCS
;	Egeom	- ECWI_GEOM struct from ECWI_TRACE_CBARS and ECWI_EXTRACT_ARCS
;	Ppar	- ECWI_PPAR pipeline parameter struct
;
; INPUT KEYWORDS:
;
; SIDE EFFECTS:
;	Modifies ECWI_GEOM struct by calculating new control points that
;	take into account the wavelength solution.
;	NOTE: sets KGEOM.STATUS to 0 if fitting succeeded, otherwise sets to
;	1 or greater depending on reason for failure (see ecwi_solve_arcs.pro).
;
; PROCEDURE:
;	Find the wavelength solution of the reference bar arc and then
;	propogate it to the other bars.  Record the wavelength solution
;	in the wavelength control points in Egeom.
;
; EXAMPLE:
;	Define the geometry from a 'cbars' image and use it to extract and 
;	display the spectra from an 'arc' image from the same calibration
;	sequence.
;
;	cbars = mrdfits('image7142_int.fits',0,chdr)
;	ecwi_trace_cbars,cbars,Egeom,/centroid
;	arc = mrdfits('image7140_int.fits',0,ahdr)
;	ecwi_extract_arcs,arc,egeom,arcspec
;	ecwi_solve_geom,arcspec,egeom,ppar
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2014-SEP-18	Initial Revision
;-
;
pro ecwi_solve_geom,spec,egeom,ppar, fitdisp=fitdisp, help=help
;
; startup
pre = 'ECWI_SOLVE_GEOM'
q = ''
;
; check inputs
if n_params(0) lt 2 or keyword_set(help) then begin
	print,pre+': Info - Usage: '+pre+', ArcSpec, Egeom'
	return
endif
;
; Check structs
if ecwi_verify_geom(egeom,/init) ne 0 then return
if ecwi_verify_ppar(ppar,/init) ne 0 then return
;
; check spec
ssz = size(spec)
if ssz[0] ne 2 or ssz[2] ne 60 then begin
	ecwi_print_info,ppar,pre,'Input spec array malformed, run ECWI_EXTRACT_ARCS first.',/error
	return
endif
;
; plot file
p_fmt = '(i0'+strn(ppar.fdigits)+')'
plfil = ppar.reddir+'wave_cb' + string(egeom.cbarsimgnum,p_fmt) + $
		       '_arc' + string(egeom.arcimgnum,p_fmt)
;
; solve arc spectra
ecwi_solve_arcs,spec,egeom,ppar,/tweak,plot_file=plfil
;
; solve transformation on slice-by-slice basis
ecwi_solve_slices,ppar,egeom
;
return
end
