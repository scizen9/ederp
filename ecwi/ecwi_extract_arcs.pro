;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_EXTRACT_ARCS
;
; PURPOSE:
;	Extract individual arc spectra along continuum bar image bars.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_EXTRACT_ARCS,ArcImg, Egeom, Spec
;
; INPUTS:
;	ArcImg	- 2-D image of type 'arc'
;	Egeom	- ECWI_GEOM struct constructed from ECWI_TRACE_CBARS run
;
; INPUT KEYWORDS:
;	NAVG	- number of pixels in x to average for each y pixel
;	CCWINDIW- cross-correlation window in pixels for offset plots
;	VERBOSE - extra output
;	DISPLAY - set to display a plot of each spectrum after shifting
;
; OUTPUTS:
;	Spec	- a array of vectors, one for each bar defined by Egeom
;
; SIDE EFFECTS:
;	None.
;
; PROCEDURE:
;	Use the Egeom.[kx,ky] coefficients to de-warp the arc image, after
;	which a spectrum is extracted by simple summing for each of the
;	bars in the 'cbars' image using the positions from Egeom.barx.  The
;	spectra are assumed aligned with dispersion along the y-axis of 
;	the image.  The extraction window in x at each y pixel is determined
;	by the keyword NAVG.  Since the spectra are extracted using whole
;	pixel windows, the reference x position for each spectrum is then
;	centered on the window center.  These are recorded in Egeom.refx.
;
; EXAMPLE:
;	Define the geometry from a 'cbars' image and use it to extract and 
;	display the spectra from an 'arc' image from the same calibration
;	sequence.
;
;	cbars = mrdfits('image7142_int.fits',0,chdr)
;	ecwi_trace_cbars,cbars,Egeom,/centroid
;	arc = mrdfits('image7140_int.fits',0,ahdr)
;	ecwi_extract_arcs,arc,egeom,arcspec,ppar
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-JUL-23	Initial Revision
;	2013-JUL-24	Checks if NASMASK in place, computes bar offsets
;	2013-DEC-09	Default nav now 2, takes median of bar sample
;-
;
pro ecwi_extract_arcs,img,egeom,spec,ppar, $
	navg=navg, ccwindow=ccwindow, $
	help=help
;
; startup
pre = 'ECWI_EXTRACT_ARCS'
q = ''
;
; check inputs
if n_params(0) lt 3 or keyword_set(help) then begin
	print,pre+': Info - Usage: '+pre+', ArcImg, Egeom, Spec'
	return
endif
;
; check Ppar
if ecwi_verify_ppar(ppar,/init) ne 0 then return
;
; Check Egeom
if ecwi_verify_geom(egeom) ne 0 then return
;
; keywords
if keyword_set(navg) then $
	nav = (fix(navg/2)-1) > 1 $
else	nav = 6
;
if keyword_set(ccwindow) then $
	ccwn = ccwindow $
else	ccwn = egeom.ccwn
do_plots = ppar.display
;
; check size of input image
sz = size(img,/dim)
if sz[0] eq 0 then begin
	ecwi_print_info,ppar,pre, $
		'input image must be 2-D, preferrably an arc image.',/error
	return
endif
nx = sz[0]
ny = sz[1]
;
; number of spectra
ns = n_elements(egeom.barx)
;
; log
ecwi_print_info,ppar,pre,'Extracting arcs from image',egeom.arcimgnum
;
; transform image
warp = poly_2d(img,egeom.kx,egeom.ky,2,cubic=-0.5)
;
; output spectra
spec = fltarr(ny,ns)
;
; bar offsets
boff = fltarr(ns)
;
; loop over x values, get sample, compute spectrum
for i=0,ns-1 do begin
	xpix = fix(egeom.barx[i])
	egeom.refx[i] = float(xpix)+0.5
	;
	; get sample
	sub = warp[(xpix-nav):(xpix+nav),*]
	;
	; compute spectrum
	vec = median(sub,dim=1)
	spec(*,i) = vec
endfor
;
; setup for display (if requested)
if do_plots ge 2 then begin
	window,0,title='ecwi_extract_arcs'
	deepcolor
	!p.background=colordex('white')
	!p.color=colordex('black')
	th=2
	si=1.75
	w=findgen(ny)
	xrng=[-ccwn,ny+ccwn]
	if egeom.nasmask eq 1 then $
			xrng = [((egeom.trimy0/egeom.ybinsize)-ccwn), $
				((egeom.trimy1/egeom.ybinsize)+ccwn)]
endif
;
; get reference bar from egeom
if egeom.refbar ge 0 and egeom.refbar lt 60 then $
	refb = egeom.refbar $
else	refb = 2	; default
;
; log
ecwi_print_info,ppar,pre,'cross-correlating with reference bar',refb
;
; cross-correlate to reference line
for i=0,ns-1 do begin
	off = 0.
	if i ne refb then $
		off = ccpeak(spec[*,i],spec[*,refb],ccwn,offset=egeom.ccoff[i/5])
	;
	; record offsets
	boff[i] = off
	;
	; log
	ecwi_print_info,ppar,pre,'Bar#, yoffset',i,off,format='(a,i4,f9.3)',info=2
	;
	; plot if requested
	if do_plots ge 2 then begin
		plot,w,spec[*,refb],thick=th,xthick=th,ythick=th, $
			charsi=si,charthi=th, $
			xran=xrng,xtitle='Pixel',xstyle=1, $
			ytitle='Int', /nodata, $
			title='Image: '+strn(egeom.arcimgnum)+ $
			', Bar: '+strn(i)+', Slice: '+strn(fix(i/5))+$
			', Y Offset: '+strtrim(string(off,form='(f9.3)'),2)+' px'
		oplot,w,spec[*,refb],color=colordex('R'),thick=th
		oplot,w+off,spec[*,i],color=colordex('G')
		ecwi_legend,['RefBar: '+strn(refb),'Bar: '+strn(i)], $
			linesty=[0,0], thick=[th,0], $
			color=[colordex('R'),colordex('G')],box=0
		read,'Next? (Q-quit plotting, <cr>-next): ',q
		if strupcase(strmid(q,0,1)) eq 'Q' then $
			do_plots = 0
	endif
endfor
;
; update Egeom
egeom.baroff = boff
;
; Egeom timestamp
egeom.progid = pre
egeom.timestamp = systime(1)
;
; clean up
if ppar.display ge 2 then wdelete,0
;
return
end
