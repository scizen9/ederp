;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_APPLY_COEFFS
;
; PURPOSE:
;	Applies wavelength solution coefficients to control points
;	for the given arc bar spectrum.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_APPLY_COEFFS,Egeom,Barno,Coeffs
;
; INPUTS:
;	Egeom	- ECWI_GEOM struct from ECWI_TRACE_CBARS and ECWI_EXTRACT_ARCS
;	Barno	- which bar spectrum to apply solution to
;
; INPUT KEYWORDS:
;	VERBOSE - extra output
;
; OUTPUTS:
;	None.
;
; SIDE EFFECTS:
;	Updates Egeom XW and YW tags to have appropriate values for input
;	wavelength solution coefficients.
;
; PROCEDURE:
;	Uses reference bar solution to define wavelength zeropoint and
;	dispersion.  Applies wavelength solution to original output control
;	points (Egeom.[xo,yo]) to derive real wavelength coordinates of
;	each, then subtracts the wavelength zeropoint and divides by the
;	reference dispersion to generate psuedo wavelength pixel coordinates.
;
; EXAMPLE:
;	Define the geometry from a 'cbars' image and use it to extract and 
;	display the spectra from an 'arc' image from the same calibration
;	sequence.
;
;	cbars = mrdfits('image7142_int.fits',0,chdr)
;	ecwi_trace_cbars,cbars,Egeom,/centroid
;	arc = mrdfits('image7140_int.fits',0,ahdr)
;	ecwi_extract_arcs,arc,egeom,arcspec,/verbose
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-JUL-31	Initial Revision
;	2013-SEP-26	Uses reference slice for output control points
;-
;
pro ecwi_apply_coeffs,egeom,barno,coeffs, $
	verbose=verbose, help=help
;
; startup
pre = 'ECWI_APPLY_COEFFS'
q = ''
;
; check inputs
if n_params(0) lt 3 or keyword_set(help) then begin
	print,pre+': Info - Usage: '+pre+', Egeom, Barno, Coeffs'
	return
endif
;
; Check Egeom
ksz = size(egeom)
if ksz[2] eq 8 then begin
	if egeom.initialized ne 1 then begin
		print,pre+': Error - Egeom struct not initialized.'
		return
	endif
endif else begin
	print,pre+': Error - Egeom not legal, run ECWI_TRACE_CBARS and ECWI_EXTRACT ARCS first.'
	return
endelse
;
; check reference solution
if total(egeom.rbcoeffs) eq 0. or egeom.rbcoeffs[0] eq 0. or $
	 egeom.rbcoeffs[1] eq 0. then begin
	print,pre+': Error - Egeom reference bar coefficients not set, run ECWI_SOLVE_ARCS first.'
	return
endif
;
; check Barno
if barno lt 0 or barno gt 119 then begin
	print,pre+': Error - Bar number out of range (0-119): ',barno
	return
endif
;
; reference bar in same slice as egeom.refbar
refbar = (barno mod 5)
;
; get control points
t=where(egeom.bar eq barno and egeom.xi gt 0.)
;
; spatial axis
; use reference slice, but adjust to left edge
refoutx = egeom.refoutx - min(egeom.refoutx) + egeom.x0out
xo = refoutx[refbar]
;
; wavelength axis
yo = egeom.yo[t]
;
; get reference wavelength
wave0 = egeom.wave0out
;
; apply coeffs
xw = xo						; nothing to apply
yw = ( poly(yo,coeffs) - wave0 ) / egeom.dwout	; apply wave soln.
;
; insert into egeom
egeom.xw[t] = xw
egeom.yw[t] = yw
;
; insert fit coeffs for this bar
fo = egeom.bfitord
egeom.bfitcoeffs[0:fo,barno] = coeffs[0:fo]
;
; Egeom timestamp
egeom.progid = pre
egeom.timestamp = systime(1)
;
return
end
