;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_APPLY_GEOM
;
; PURPOSE:
;	Apply the final geometric transformation to an input image.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_APPLY_GEOM,Img, Hdr, Egeom, Ppar, Cube, CubeHdr
;
; INPUTS:
;	Img	- Stage1 processed object image to apply geometry to
;	Hdr	- the corresponding header of the input image
;	Egeom	- ECWI_GEOM struct after ECWI_SOLVE_ARCS has been run
;
; INPUT KEYWORDS:
;	VERBOSE - extra output
;
; OUTPUTS:
;	Cube	- 3-D data cube image [slice,x,wavelength]
;	CubeHdr	- A fits header with WCS info from Egeom
;
; SIDE EFFECTS:
;	None.
;
; PROCEDURE:
;	Apply the geomtric transformation in Egeom to Img and copy Hdr to
;	CubeHdr and update WCS keywords.
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-JUL-31	Initial Revision
;	2013-AUG-07	Added padding of input image to extend output slices
;	2013-OCT-02	Re-ordered output cube axes and added WCS
;       2015-APR-25     Added CWI flexure hooks (MM)
;-
; CWI FLEX CHANGE ++
pro ecwi_apply_geom,img,hdr,egeom,ppar,cube,chdr, $
	diag_cube=diag_cube, flex=flex
; CWI FLEX CHANGE --
;
; startup
pre = 'ECWI_APPLY_GEOM'
q = ''
;
; Check structs
if ecwi_verify_geom(egeom,/init) ne 0 then return
if ecwi_verify_ppar(ppar) ne 0 then begin
	ppar = {ecwi_ppar}
endif
;
; CWI FLEX ADDITION +++
doflex = 0
if size(flex, /type) eq 8 then begin
   if flex.computed eq 1 then doflex = 1 else doflex = 0
endif else doflex = 0  
; CWI FLEX ADDITION ---
;
; get image original size
sz = size(img,/dim)
;
; get the padding for image
pad = egeom.ypad
;
; get low trim wavelength
wave0 = egeom.wave0out
;
; get high trim pixel
lastpix = long ( ( egeom.wave1out - egeom.wave0out ) / egeom.dwout )
;
; pad image to include full slices
pimg = fltarr(sz[0],sz[1]+pad+pad)
;
; insert original
y0 = pad
y1 = (sz[1]-1) + pad
pimg[*,y0:y1] = img
;
; get slice size
sli = where(egeom.slice eq 0 and egeom.xi gt 0)
xw = egeom.xw[sli]
xcut = fix(4.*egeom.refdelx + 2.*egeom.x0out)
;
; log values
ecwi_print_info,ppar,pre,'Slice dimensions (x,y)',xcut+1l,lastpix+1l, $
	format='(a,2i9)'
;
; image number
imgnum = sxpar(hdr,'IMGNUM')
object = sxpar(hdr,'OBJECT')
imgtyp = sxpar(hdr,'IMGTYPE')
;
; log
ecwi_print_info,ppar,pre,'Slicing and dicing image '+strn(imgnum)+': '+object+'...'
;
; loop over slices
for i=0,11 do begin
	sli = where(egeom.slice eq i)
        ;
        ; CWI FLEX ADDITION +++
        if doflex then begin
           kwx = flex.kwx_new[*,*,i]
           kwy = flex.kwy_new[*,*,i]
        endif else begin
           kwx = egeom.kwx[*,*,i]
           kwy = egeom.kwy[*,*,i]
        endelse; egeom.kw(x/y)
        warp = poly_2d(pimg,kwx,kwy,2,cubic=-0.5)
        ; CWI FLEX ADDITION ---
        ;
	; check dimensions
	wsz = size(warp,/dim)
	;
	; are we too big?
	if i eq 0 and xcut ge wsz[0] then $
		ecwi_print_info,ppar,pre,'xcut gt xsize',xcut,wsz[0], $
			format='(a,2i13)',/warning
	if i eq 0 and lastpix ge wsz[1] then $
		ecwi_print_info,ppar,pre,'lastpix gt ysize',lastpix,wsz[1], $
			format='(a,2i13)',/warning
	;
	; trim slice
	slice = warp[0:xcut<(wsz[0]-1),0:lastpix<(wsz[1]-1)]
	if i eq 0 then begin
		sz = size(slice,/dim)
		cube = fltarr(sz[0],12,sz[1])
		diag_cube = fltarr(sz[0],sz[1],12)
	endif
	cube[*,i,*] = reverse(slice,1)
	diag_cube[*,*,i] = slice
	if ppar.verbose eq 1 then $
		print,strn(i)+' ',format='($,a)'
endfor
if ppar.verbose eq 1 then begin
	print,'Done.',format='($,a)'
	print,''
endif
;
; update header
chdr = hdr
;
; image dimensions
sxaddpar,chdr,'NAXIS',3
sxaddpar,chdr,'NAXIS1',sz[0]
sxaddpar,chdr,'NAXIS2',12
sxaddpar,chdr,'NAXIS3',sz[1],' length of data axis 3',after='NAXIS2'
;
; spatial scale and zero point
sxaddpar,chdr,'BARSEP',egeom.refdelx,' separation of bars (binned pix)'
sxaddpar,chdr,'BAR0',egeom.x0out,' first bar pixel position'
;
; wavelength ranges
sxaddpar,chdr, 'WAVALL0', egeom.waveall0, ' Low inclusive wavelength'
sxaddpar,chdr, 'WAVALL1', egeom.waveall1, ' High inclusive wavelength'
sxaddpar,chdr, 'WAVGOOD0',egeom.wavegood0, ' Low good wavelength'
sxaddpar,chdr, 'WAVGOOD1',egeom.wavegood1, ' High good wavelength'
sxaddpar,chdr, 'WAVMID',egeom.wavemid, ' middle wavelength'
;
; wavelength solution RMS
sxaddpar,chdr,'AVWVSIG',egeom.avewavesig,' Avg. bar wave sigma (Ang)'
sxaddpar,chdr,'SDWVSIG',egeom.stdevwavesig,' Stdev. bar wave sigma (Ang)'
;
; geometry solution RMS
for i=0,11 do begin
	sxaddpar,chdr, 'GEOXSG'+strn(i), egeom.xrsd[i],' Avg. geometry X sigma (pix) slice '+strn(i),format='F7.3'
	sxaddpar,chdr, 'GEOYSG'+strn(i), egeom.yrsd[i],' Avg. geometry Y sigma (pix) slice '+strn(i),format='F7.3'
endfor
;
; pixel scales
sxaddpar,chdr,'PXSCL', egeom.pxscl*egeom.xbinsize,' Pixel scale along slice'
sxaddpar,chdr,'SLSCL', egeom.slscl,' Pixel scale purpendicular to slices'
;
; geometry origins
sxaddpar,chdr, 'CBARSFL', egeom.cbarsfname,' Continuum bars image'
sxaddpar,chdr, 'ARCFL',   egeom.arcfname, ' Arc image'
sxaddpar,chdr, 'CBARSNO', egeom.cbarsimgnum,' Continuum bars image number'
sxaddpar,chdr, 'ARCNO',   egeom.arcimgnum, ' Arc image number'
sxaddpar,chdr, 'GEOMFL',  egeom.geomfile,' Geometry file'
;
; get sky coords
ra = sxpar(hdr,'RA',count=nra)
dec = sxpar(hdr,'DEC',count=ndec)
if nra ne 1 or ndec ne 1 then begin
	ra = sxpar(hdr,'TARGRA',count=nra)
	dec = sxpar(hdr,'TARGDEC',count=ndec)
endif
;
; Position Angle ( = -ROTPA) in radians
crota = -sxpar(hdr,'ROTPA',count=npa) / !RADEG
;
; pixel scales
cdelt1 = -egeom.pxscl*egeom.xbinsize	; RA degrees per px (column)
cdelt2 = egeom.slscl			; Dec degrees per slice (row)
;
; did we get good coords?
if nra ne 1 or ndec ne 1 or npa ne 1 then begin
	;
	; no good coords
	ecwi_print_info,ppar,pre,'no coords for image',imgnum,imgtyp, $
		format='(a,2x,a,2x,a)',/warning
	;
	; zero coords
	ra = 0.
	dec = 0.
	;
	; zero CD matrix
	CD11 = 0.
	CD12 = 0.
	CD21 = 0.
	CD22 = 0.
endif else begin
	;
	; calculate CD matrix
	CD11 = cdelt1*cos(crota)			; RA degrees per column
	CD12 = abs(cdelt2)*sign(cdelt1)*sin(crota)	; RA degress per row
	CD21 = -abs(cdelt1)*sign(cdelt2)*sin(crota)	; DEC degress per column
	CD22 = cdelt2*cos(crota)			; DEC degrees per row
endelse
;
; get reference pixels
if ppar.crpix1 le 0. then $
	crpix1 = sz[0]/2. $	; spatial slit direction
else	crpix1 = ppar.crpix1
if ppar.crpix2 le 0. then $
	crpix2 = 6. $		; spatial slice direction: 12/2
else	crpix2 = ppar.crpix2
if ppar.crpix3 le 0. then $
	crpix3 = 1. $		; wavelength direction
else	crpix3 = ppar.crpix3
;
; WCS keywords
sxaddpar,chdr,'WCSDIM',3,' number of dimensions in WCS'
sxaddpar,chdr,'WCSNAME','ECWI'
sxaddpar,chdr,'EQUINOX',2000.
sxaddpar,chdr,'RADESYS','FK5'
sxaddpar,chdr,'CTYPE1','RA---TAN'
sxaddpar,chdr,'CTYPE2','DEC--TAN'
sxaddpar,chdr,'CTYPE3','AWAV',' Air Wavelengths'
sxaddpar,chdr,'CUNIT1','deg',' RA units'
sxaddpar,chdr,'CUNIT2','deg',' DEC units'
sxaddpar,chdr,'CUNIT3','Angstrom',' Wavelength units'
sxaddpar,chdr,'CNAME1','ECWI RA',' RA name'
sxaddpar,chdr,'CNAME2','ECWI DEC',' DEC name'
sxaddpar,chdr,'CNAME3','ECWI Wavelength',' Wavelength name'
sxaddpar,chdr,'CRVAL1',ra,' RA zeropoint'
sxaddpar,chdr,'CRVAL2',dec,' DEC zeropoint'
sxaddpar,chdr,'CRVAL3',wave0,' Wavelength zeropoint'
sxaddpar,chdr,'CRPIX1',crpix1,' RA reference pixel'
sxaddpar,chdr,'CRPIX2',crpix2,' DEC reference pixel'
sxaddpar,chdr,'CRPIX3',crpix3,' Wavelength reference pixel'
sxaddpar,chdr,'CD1_1',cd11,' RA degrees per column pixel'
sxaddpar,chdr,'CD2_1',cd21,' DEC degrees per column pixel'
sxaddpar,chdr,'CD1_2',cd12,' RA degrees per row pixel'
sxaddpar,chdr,'CD2_2',cd22,' DEC degrees per row pixel'
sxaddpar,chdr,'CD3_3',egeom.dwout,' Wavelength Angstroms per pixel'
sxaddpar,chdr,'LONPOLE',180.0,' Native longitude of Celestial pole'
sxaddpar,chdr,'LATPOLE',0.0,' Celestial latitude of native pole'
sxaddpar,chdr,'COMMENT','  '+egeom.progid
sxaddpar,chdr,'COMMENT','  '+pre+' '+systime(0)
;
return
end
