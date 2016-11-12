;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_SOLVE_SLICES
;
; PURPOSE:
;	Solves the geometric transformation for each slice.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_SOLVE_SLICES,Ppar,Egeom
;
; INPUTS:
;	Egeom	- ECWI_GEOM struct from ECWI_TRACE_CBARS and ECWI_EXTRACT_ARCS
;	Ppar	- ECWI_PPAR pipeline parameter struct
;
; INPUT KEYWORDS:
;	HELP	- display usage help and exit
;
; OUTPUTS:
;	None.
;
; SIDE EFFECTS:
;	Updates Egeom KWX and KWY geomtric transformation coefficients.
;
; PROCEDURE:
;	The Egeom KWX and KWY geomtric transformation coefficients are fit
;	with POLYWARP based on control points in Egeom XI,YI,XW,YW for 
;	each slice.
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
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-JUL-31	Initial Revision
;	2013-AUG-12	Added low pixel end padding
;	2014-SEP-11	Now pass ppar
;-
;
pro ecwi_solve_slices,ppar,egeom, help=help
;
; setup
pre = 'ECWI_SOLVE_SLICES'
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
if egeom.status ne 0 then begin
	ecwi_print_info,ppar,pre,'Egeom fit no good.',/error
	return
endif
;
; diagnostic plots
display = (ppar.display ge 4)
if display then begin
	window,0,title='ecwi_solve_slices'
	!p.multi=[0,1,2]
endif
;
; degree
if egeom.nasmask eq 1 then $
	degree = 3 $
else	degree = 3
;
; loop over slices
for i=0,11 do begin
	sli = where(egeom.slice eq i and egeom.xi gt 0. and $
		    finite(egeom.xw) and finite(egeom.yw), nsli)
	if nsli le 0 then begin
		ecwi_print_info,ppar,pre,'Egeom slice index error.',/error
		return
	endif
	;
	; get control points
	xi = egeom.xi[sli]
	yi = egeom.yi[sli] + egeom.ypad	; pad to avoid data cutoff
	xw = egeom.xw[sli]
	yw = egeom.yw[sli]
	;
	; fit
	polywarp,xi,yi,xw,yw,degree,kwx,kwy,/double,status=status
	;
	; get residuals
	ecwi_geom_resid,xi,yi,xw,yw,degree,kwx,kwy,xrsd,yrsd
	;
	; check status
	if status ne 0 then $
		ecwi_print_info,ppar,pre,'Polywarp non-zero status: ',status, $
			/warning
	;
	; insert into egeom
	egeom.kwx[0:degree,0:degree,i] = kwx
	egeom.kwy[0:degree,0:degree,i] = kwy
	;
	; insert residuals
	xmo = moment(xrsd,/nan)
	ymo = moment(yrsd,/nan)
	egeom.xrsd[i] = sqrt(xmo[1])
	egeom.yrsd[i] = sqrt(ymo[1])
	;
	; plot if requested
	if display then begin
		tlab = 'Slice '+strn(i) + ':' + $
			' Xsig = '+string(egeom.xrsd[i], format='(f7.3)') + $
			' Ysig = '+string(egeom.yrsd[i], format='(f7.3)')
		;
		; x residuals
		xrng=get_plotlims(xw)
		yrng = [min([min(xrsd),-0.2]),max([max(xrsd),0.2])]
		plot,xw,xrsd,psym=4,title=tlab, $
			xran=xrng,/xs,xtitle='X coord (pix)', $
			yran=yrng,/ys,ytitle='X rsd (pix)'
		oplot,!x.crange,[0,0],linesty=0
		oplot,!x.crange,[xmo[0],xmo[0]],linesty=2
		oplot,!x.crange,[xmo[0]+egeom.xrsd[i],xmo[0]+egeom.xrsd[i]],linesty=2
		oplot,!x.crange,[xmo[0]-egeom.xrsd[i],xmo[0]-egeom.xrsd[i]],linesty=2
		;
		; y residuals
		yw = yw*egeom.dwout + egeom.wave0out
		xrng=get_plotlims(yw)
		yrng = [min([min(yrsd),-0.2]),max([max(yrsd),0.2])]
		plot,yw,yrsd,psym=4, $
			xran=xrng,/xs,xtitle='Y coord (Ang)', $
			yran=yrng,/ys,ytitle='Y rsd (pix)'
		oplot,!x.crange,[0,0],linesty=0
		oplot,!x.crange,[ymo[0],ymo[0]],linesty=2
		oplot,!x.crange,[ymo[0]+egeom.yrsd[i],ymo[0]+egeom.yrsd[i]],linesty=2
		oplot,!x.crange,[ymo[0]-egeom.yrsd[i],ymo[0]-egeom.yrsd[i]],linesty=2
		read,'Next? (Q - quit plotting, <cr> - next): ',q
		if strupcase(strmid(q,0,1)) eq 'Q' then display = (1 eq 0)
	endif	; display
endfor	; loop over slices
;
; Egeom timestamp
egeom.progid = pre
egeom.timestamp = systime(1)
;
if ppar.display ge 4 then $
	!p.multi=0
;
return
end
