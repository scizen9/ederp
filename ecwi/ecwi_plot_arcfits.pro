;
; Copyright (c) 2014, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_PLOT_ARCFITS
;
; PURPOSE:
;	plot arc wavelength solution diagnostics
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_PLOT_ARCFITS, Specs, Egeom, Ppar, CntCoeff, FinCoeff, Sigmas
;
; INPUTS:
;	Specs	- a array of arc spectra produced by ECWI_EXTRACT_ARCS
;	Egeom	- ECWI_GEOM struct from ECWI_TRACE_CBARS and ECWI_EXTRACT_ARCS
;	Ppar	- ECWI_PPAR pipeline parameter struct
;	CntCoeff - Coefficients from fits to central region
;	FinCoeff - Coefficients from fits to full region
;	Sigmas	- Line center residuals (Ang) of fits
;
; INPUT KEYWORDS:
;	TWEAK	- set to indicate the fits are from iteratively tweaked fits
;	PLOT_FILE - if set to a string, will be used to produce postscript 
;		output of diagnostic plots
;
; SIDE EFFECTS:
;	outputs postscript plot file specified in PLOT_FILE
;
; PROCEDURE:
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;	Written by:	Matt Matuszewski, Don Neill
;	2014-SEP-19	Initial Revision
;-
;
pro ecwi_plot_arcfits, specs, egeom, ppar, cntcoeff, fincoeff, sigmas, $
	fwaves, dwaves, $
	tweak=tweak, plot_file=plot_file

pre = 'ECWI_PLOT_ARCFITS'
q=''
;
; do we want to display stuff? 
display = (ppar.display ge 2 or keyword_set(plot_file))
;
; what to do if we are not plotting or displaying
if not display then return
;
; which image number
imgnum = egeom.arcimgnum
imglab = 'Img # '+strn(imgnum)+' Fl: '+strtrim(egeom.filter,2)+' Gr: '+strtrim(egeom.gratid,2)
;
; is the N+S mask in?
nasmask = egeom.nasmask
;
; degree defaults to 3 for central region fit
degree = 3
;
; check if we need the last degree for full-ccd tweaked fits
if keyword_set(tweak) and not nasmask then $
	degree = egeom.lastdegree
;
; fit type
if nasmask then $
	fittype = 'Central' $
else	fittype = 'FullCCD'
;
; load the reference atlas spectrum.
ecwi_read_atlas,egeom,ppar,refspec,refwvl,refdisp
;
; input spectrum dimensions
specsz = size(specs,/dim)
;
; set up array with zero point in the center
x0 = specsz[0]/2
fxvals = dindgen(specsz[0])	; fullCCD xvals
cxvals = fxvals-x0		; central xvals
;
; if not making hardcopy, open a new window
if not keyword_set(plot_file) then $
	window,1,title='ecwi_plot_arcfits'
;
; set up plots
!p.multi=0
if keyword_set(plot_file) then begin
	psfile,plot_file
	!p.multi=[0,1,2]
	ecwi_print_info,ppar,pre,'plotting diagnostics to: '+plot_file+'.ps'
endif
deepcolor
!p.background=colordex('white')
!p.color=colordex('black')
th=2.0
si=2.0
;
; get good bars
bargood = where(sigmas ge 0., nbargood)
;
; bad bars
barbad = where(sigmas lt 0., nbarbad)
;
; number of comparison lines
nlines = intarr(60)
;
; first plot sigmas
if keyword_set(tweak) then begin 
	;
	; get fit rms status
	mom = moment(sigmas[bargood])
	fitrmslab = strtrim(string(mom[0],format='(f9.3)'),2) + ' +- ' + $
	      strtrim(string(sqrt(mom[1]),format='(f9.3)'),2)
	;
	; set title
	tlab=imglab+', '+fittype+' Fit <RMS>: ' + fitrmslab
	;
	; plot range
	yrng = get_plotlims(sigmas[bargood])
	;
	plot,sigmas,psym=4,title=tlab, $
		xtitle='Bar #',xrange=[-1,60],/xs, $
		ytitle='RMS (Ang)',yrange=yrng,/ys
	oplot,!x.crange,[mom[0],mom[0]],linesty=5,thick=th
	oplot,!x.crange,[mom[0]+sqrt(mom[1]),mom[0]+sqrt(mom[1])],linesty=1,thick=th
	oplot,!x.crange,[mom[0]-sqrt(mom[1]),mom[0]-sqrt(mom[1])],linesty=1,thick=th
	if nbarbad gt 0 then $
		oplot,barbad,replicate(mom[0],nbarbad),psym=7,thick=th
	ecwi_oplot_slices
	;
	; next
	if not keyword_set(plot_file) then $
		read,'next: ',q
	;
	; plot number of lines
	for b = 0,59 do begin
		ffwaves = reform(fwaves[b,*])
		li = where(ffwaves gt 0, nli)
		nlines[b] = nli
	endfor
	mom = moment(nlines)
	fitnlslab = strtrim(string(mom[0],format='(f9.1)'),2) + ' +- ' + $
	      strtrim(string(sqrt(mom[1]),format='(f9.1)'),2)
	;
	; set title
	tlab=imglab+', '+fittype+' Fit <N Lines>: ' + fitnlslab
	;
	; plot range
	yrng = get_plotlims(nlines)
	;
	plot,nlines,psym=4,title=tlab, $
		xtitle='Bar #',xrange=[-1,60],/xs, $
		ytitle='N Lines',yrange=yrng,/ys
	oplot,!x.crange,[mom[0],mom[0]],linesty=5,thick=th
	oplot,!x.crange,[mom[0]+sqrt(mom[1]),mom[0]+sqrt(mom[1])],linesty=1,thick=th
	oplot,!x.crange,[mom[0]-sqrt(mom[1]),mom[0]-sqrt(mom[1])],linesty=1,thick=th
	if nbarbad gt 0 then $
		oplot,barbad,replicate(mom[0],nbarbad),psym=7,thick=th
	ecwi_oplot_slices
	;
	; next
	if not keyword_set(plot_file) then $
		read,'next: ',q
endif
;
; plot each coeff
for i=0,degree do begin
	if display then begin
		;
		; set title
		tlab = imglab + ', '+fittype+' '+strn(i)
		;
		; set y title
		if i eq 0 then begin
			ylab = 'Ang'
		endif else if i eq 1 then begin
			ylab = 'Ang/pix'
		endif else begin
			ylab = 'Ang/pix^'+strn(i)
		endelse
		;
		; plot range
		yrng = get_plotlims(fincoeff[i,*])
		;
		plot,fincoeff[i,*],psym=4,title=tlab, $
			xtitle='Bar #',xrange=[-1,60],/xs, $
			ytitle=ylab,yrange=yrng,/ys
		if nbarbad gt 0 then $
			oplot,barbad,fincoeff[i,barbad],psym=7,thick=th
		ecwi_oplot_slices
		if not keyword_set(plot_file) then begin
			read,'Next? (Q-quit plotting, <cr> - next): ',q
			if strupcase(strmid(q,0,1)) eq 'Q' then $
				display = (1 eq 0)
		endif
	endif	; display?
endfor
;
if not keyword_set(plot_file) then $
	!p.multi = 0 $
else	!p.multi = [0,1,2]
;
; inclusive, all, and trim wavelengths
wavall0 = egeom.waveall0
wavall1 = egeom.waveall1
wavgood0 = egeom.wavegood0
wavgood1 = egeom.wavegood1
wavmid = egeom.wavemid
cwave = egeom.cwave
minwav = egeom.wave0out
maxwav = egeom.wave1out
;
; atlas name
atnam = egeom.refname
;
; loop over each bar
for b=0,59 do begin
	;
	; are we displaying or plotting?
	if display or keyword_set(plot_file) then begin
		;
		; fullCCD or Central?
		if not nasmask then begin
			cf = fincoeff[*,b]
			pcolor = colordex('blue')
			rcolor = colordex('s')
			xvals = fxvals
		endif else begin
			cf = cntcoeff[*,b]
			pcolor = colordex('red')
			rcolor = colordex('pink')
			xvals = cxvals
		endelse
		;
		; check coeffs
		gcf = where(finite(cf) eq 1, ngcf)
		;
		; generate wavelengths
		if ngcf gt 0 then $
			waves = poly(xvals,cf[gcf]) $
		else	waves = replicate(0.,n_elements(xvals))
		;
		; mark off good regions for plot limits
		ta = where(refwvl ge wavgood0 and refwvl le wavgood1)
		ts = where(waves ge wavgood0 and waves le wavgood1,nts)
		;
		; are there good object wavelengths?
		if nts gt 0 then begin
			yrng = get_plotlims(specs[ts,b],/minzero)
			fac = max(refspec[ta])/max(specs[ts,b])
		endif else begin
			yrng = get_plotlims(refspec[ta],/minzero)
			fac = 1.
		endelse
		tlab = imglab + ', Bar = '+string(b,"(i03)") + $
			', Slice = '+string(fix(b/5),"(i02)")
		if keyword_set(tweak) and sigmas[b] gt 0 then begin
			ddwaves = reform(dwaves[b,*])
			ffwaves = reform(fwaves[b,*])
			li = where(ffwaves gt 0, nli)
			if nli gt 0 then begin
				ffwaves = ffwaves[li]
				ddwaves = ddwaves[li]
			endif else nli = 0
			tlab = tlab + ', RMS = '+string(sigmas[b],"(f5.3)") + $
				', N = '+strn(nli)
		endif else nli = 0
		plot,refwvl,refspec/fac,thick=th,charthi=th, title=tlab, $
			xthick=th,xtitle='Wavelength (A)',xrange=[minwav,maxwav],/xs, $
			ythick=th,ytitle='Flux',yrange=yrng,/ys
		oplot,waves,smooth(specs[*,b],5),color=pcolor,thick=1.0
		oplot,[wavgood0,wavgood0],!y.crange,color=colordex('green'),linesty=1,thick=th
		oplot,[wavgood1,wavgood1],!y.crange,color=colordex('green'),linesty=1,thick=th
		oplot,[wavall0,wavall0],!y.crange,color=colordex('orange'),linesty=1,thick=th
		oplot,[wavall1,wavall1],!y.crange,color=colordex('orange'),linesty=1,thick=th
		oplot,[wavmid,wavmid],!y.crange,color=colordex('green'),linesty=1,thick=th
		oplot,[cwave,cwave],!y.crange,color=colordex('black'),linesty=1,thick=th
		;
		; plot lines used for RMS calc
		if keyword_set(tweak) and nli gt 0 then begin
			ffwaves = ffwaves[li]
			ddwaves = ddwaves[li]
			for i=0,nli-1 do $
				oplot,[ffwaves[i],ffwaves[i]],!y.crange,color=rcolor
		endif
		ecwi_legend,[atnam+' Atlas',fittype+' Arc Fit'],linesty=[0,0],charthi=th, $
			color=[colordex('black'),pcolor], $
			thick=[th,th],/clear,clr_color=!p.background
		;
		if not keyword_set(plot_file) then begin
			read,'Next? (Q-quit plotting, <cr> - next): ',q
			if strupcase(strmid(q,0,1)) eq 'Q' then $
				display = (1 eq 0)
		endif
		;
		; plot residuals
		if keyword_set(tweak) and display then begin
			residrng = get_plotlims(ddwaves)
			resrng = [residrng[0]<(-0.2),residrng[1]>0.2]
			plot,ffwaves,ddwaves,psym=4,charthi=th,thick=th, $
				xthick=th,xtitle='Wave(Ang)',xrange=[minwav,maxwav],/xs, $
				ythick=th,ytitle='Resid(Ang)',yrange=resrng,/ys, $
				title=tlab,/nodata
			oplot,!x.crange,[0,0]
			oplot,[wavgood0,wavgood0],!y.crange,color=colordex('green'),linesty=1,thick=th
			oplot,[wavgood1,wavgood1],!y.crange,color=colordex('green'),linesty=1,thick=th
			oplot,[wavall0,wavall0],!y.crange,color=colordex('orange'),linesty=1,thick=th
			oplot,[wavall1,wavall1],!y.crange,color=colordex('orange'),linesty=1,thick=th
			oplot,[wavmid,wavmid],!y.crange,color=colordex('green'),linesty=1,thick=th
			oplot,[cwave,cwave],!y.crange,color=colordex('black'),linesty=1,thick=th
			if nli gt 0 then begin
				oplot,ffwaves,ddwaves,psym=4,thick=th
				oplot,!x.crange,[sigmas[b],sigmas[b]],linesty=2
				oplot,!x.crange,-[sigmas[b],sigmas[b]],linesty=2
			endif
			ecwi_legend,['All','Good','CWAVE'],linesty=[1,1,1],charthi=th, $
				color=[colordex('orange'),colordex('green'),colordex('black')], $
				thick=[th,th,th],/clear,clr_color=!p.background
			;
			if not keyword_set(plot_file) then begin
				read,'Next? (Q-quit plotting, <cr> - next): ',q
				if strupcase(strmid(q,0,1)) eq 'Q' then $
					display = (1 eq 0)
			endif
		endif	; are we plotting residuals?
	endif	; display or keyword_set(plot_file)
endfor		;b

if keyword_set(plot_file) then $
	psclose $
else	wdelete,1
;
!p.multi=0
;
return
end		; ecwi_plot_arcfits
