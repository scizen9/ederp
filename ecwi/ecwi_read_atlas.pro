;
; Copyright (c) 2014, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_READ_ATLAS
;
; PURPOSE:
;	Read the atlas spectrum and convolve to nominal ECWI resolution
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_READ_ATLAS, Egeom, Ppar, Refspec, Refwave, Refdisp
;
; INPUTS:
;	Egeom	- ECWI_GEOM struct from ECWI_TRACE_CBARS and ECWI_EXTRACT_ARCS
;	Ppar	- ECWI_PPAR pipeline parameter struct
;
; OUTPUTS:
;	Refspec	- Atlas reference spectrum
;	Refwave	- Atlas reference spectrum wavelengths
;	Refdisp	- Atlas reference spectrum dispersion in Ang/px
;
; INPUT KEYWORDS:
;
; SIDE EFFECTS:
;
; PROCEDURE:
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill
;	2014-SEP-18	Initial Revision
;-
;
pro ecwi_read_atlas, egeom, ppar, refspec, refwave, refdisp

pre = 'ECWI_READ_ATLAS'
q=''
;
; init
refspec = -1.
refwave = -1.
refdisp = -1.
;
; check inputs
if ecwi_verify_geom(egeom,/init) ne 0 then return
if ecwi_verify_ppar(ppar,/init) ne 0 then return
;
; canonical resolution?
resolution = egeom.resolution
;
; check if file is available
if not file_test(egeom.refspec,/read,/regular) then begin
	ecwi_print_info,ppar,pre,'Atlas spectrum file not found',egeom.refspec,$
		format='(a,a)',/error
	return
endif
;
; load the reference atlas spectrum.
rdfits1dspec,egeom.refspec,refwave,atlas, $
	wavezero=refw0, deltawave=refdisp, refpix=refpix
refspec = atlas>0  
;
; we want to degrade this spectrum to the instrument resolution
xx = findgen(99)-50.0d
fwhm = resolution/refdisp
gaus = gaussian(xx,[1.0,0.0,fwhm/2.355])
gaus /= total(gaus)
refspec = convolve(refspec,gaus)
;
return
end		; ecwi_read_atlas
