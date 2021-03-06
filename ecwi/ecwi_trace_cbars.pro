;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_TRACE_CBARS
;
; PURPOSE:
;	This procedure traces the bars in the continuum bars (cbars)
;	type calibration images and generates a geometric solution.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_TRACE_CBARS,Img,Egeom,WarpIm
;
; INPUTS:
;	Img	- 2-D image of type 'cbars'
;
; INPUT KEYWORDS:
;	PWDEG	- degree of POLYWARP geometric solution
;	PKBUF	- number of pixels on each side of peak to use
;	STEPSIZE- number of pixel rows to step in tracing peaks in y direction
;	AVGROWS - number of rows to average when tracing at each step
;	CENTROID- use Centroid only to find peaks (default)
;	GAUSS	- use Gaussian to fit peaks
;	MOFFAT	- use Moffat function to fit peaks
;
; OUTPUT KEYWORDS:
;	WARPIM	- warped version of input image
;
; OUTPUTS:
;	Egeom	- ECWI geometric transformation struct 
;			(see ECWI_GEOM__DEFINE.PRO)
;
; SIDE EFFECTS:
;	None.
;
; PROCEDURE:
;	Starts by defining peaks from middle row of image.  It then
;	traces the bars upward and then downward in steps to generate
;	a grid of control points that are sent to POLYWARP, which
;	generates the Kx, Ky coefficients that are sent to POLY_2D.
;
; NOTE:
;	Assumes the input image has already been through stage1 (see
;	ECWI_STAGE1.PRO).
;
; EXAMPLE:
;	
;	Read in a reduced image and generate a warped image and the
;	corresponding coefficients using a Moffat function to fit the
;	peaks in each row.
;
;	img = mrdfits('image7060_int.fits',0,hdr,/fscale)
;	ecwi_trace_cbars,img,egeom,ppar,/moffat
;
; TODO:
;	Use canonical 'center row' so spatial coords don't vary
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-JUL-12	Initial version
;	2013-JUL-17	Added keywords, condition on warp output
;	2013-JUL-18	Now finds canonical number of peaks (120)
;	2013-JUL-23	Renamed and updated arguments and keywords
;	2013-SEP-14	Use ppar to pass loglun
;	2013-NOV-08	Use median of navg pixels instead of total to reject CRs
;	2014-JAN-30	Handle dome flat scattered light
;	2014-APR-09	Robust check for single-pixel peaks
;	2014-OCT-30	Bar detection now starts at half peak and decriments
;-
forward_function trace_u

function trace_u, x, p
	wid = abs(p[2]) > 1e-20
	return, ((x-p[1])/wid)
end

pro ecwi_trace_cbars, img, egeom, ppar, $
	warpim=warpim, pwdeg=pwdeg, pkbuf=pkbuf, stepsize=stepsize, $
	avgrows=avgrows, gauss=gauss, moffat=moffat, centroid=centroid, $
	status=status, help=help
;
; init
pre = 'ECWI_TRACE_CBARS'
q=''
status = -1
;
; check inputs
if n_params(0) lt 2 or keyword_set(help) then begin
	print,pre+': Info - Usage: '+pre+', CBarsImg, Egeom, [Ppar]'
	return
endif
if n_params(0) lt 3 then begin
	ppar = { ecwi_ppar }
	ppar = struct_init(ppar)
endif
;
; check keywords
nter = 4
if keyword_set(moffat) then nter=5
pdeg = 3
if keyword_set(pwdeg) then pdeg=pwdeg
pbuf = 5
if keyword_set(pkbuf) then pbuf=pkbuf
step = 80/egeom.ybinsize
if keyword_set(stepsize) then step=stepsize
navg = 30
if keyword_set(avgrows) then navg=avgrows
do_plots = ppar.display
;
; prepare plots, if needed
if do_plots ge 1 then begin
	window,0,title='ecwi_trace_cbars'
	deepcolor
	!p.background=colordex('white')
	!p.color=colordex('black')
endif
;
; check image size
sz=size(img,/dim)
if sz[0] eq 0 then begin
	ecwi_print_info,ppar,pre, $
		'input image must be 2-D, preferrably a cbars image.', $
		/error
	return
endif
;
; check Egeom
if ecwi_verify_geom(egeom,/silent) ne 0 then begin
; not a struct so get a shiny, new one
	egeom = { ecwi_geom }
	egeom = struct_init(egeom)
endif
;
; log
ecwi_print_info,ppar,pre,'Tracing bars in image number',egeom.cbarsimgnum
;
; number of measurements per peak
npts = sz[1]/step
;
; which rows to measure?
peaky = indgen(npts)*step + fix(step/2)
;
; ensure we don't run off image
while max(peaky) ge sz[1]-navg do begin
	npts = npts - 1
	peaky = indgen(npts)*step+fix(step/2)
endwhile
;
; get middle row
print,pre+': Info - Finding peaks in middle row...'
p0 = npts/2
y0 = peaky[p0]
midrow = y0
;
row = reform(median(img[*,(y0-navg):(y0+navg)],dimen=2))
nrpts = n_elements(row)
;
; get rough background vector
win = 50
backv = row-row
for i=win/2,nrpts-win/2-1 do $
	backv[i] = min(row[i-win/2:i+win/2-1])
backv[0:win/2-1] = backv[win/2]
backv[nrpts-win/2:*] = backv[nrpts-win/2-1]
;
; subtract
;row = row - backv
;
; row maximum
rowmax = max(row)
;
; get sky and skysig
mmm,row,sky,skysig,/silent
;
; check sky value, if fails use brute-force histogram peak
if sky lt min(row) then begin
	rhist = histogram(row,min=0.)
	t = where(rhist eq max(rhist))
	sky = float(t[0])
endif
;
; check for zero skysig
if skysig le 0. then $
	skysig = max(row)*0.01
;
ecwi_print_info,ppar,pre,'Sky, SkySig',sky,skysig
;
; make sure we are above sky + 10.*skysig
skylim =  sky + skysig
;
; find 60 peaks
smul = 0.1
npks = 0
tries = 0
;
; start at half peak, but above sky limit
;barth = rowmax*smul>skylim
barth = rowmax*smul>skylim
while npks ne 60 and tries lt 10 do begin
	pks = findpeaks(findgen(n_elements(row)),row,7,0.003,barth,15, $
		count=npks)
	;
	; too many peaks?
	if npks gt 60 then begin
		;
		; loop through and enforce a minimum separation of bars
		done = (1 eq 0)
		while not done do begin
			;
			; good array
			gp = intarr(npks) + 1
			pp = 0
			done2 = (1 eq 0)
			;
			; look at each separation
			while not done2 do begin
				po = pks[pp+1] - pks[pp]
				;
				; we've found a baddie
				if po lt 29. then begin
					;
					; extract it from the set
					gp[pp+1] = 0
					good = where(gp eq 1, npks)
					pks = pks[good]
					;
					; start the examination again
					done2 = (1 eq 1)
				endif else pp += 1	; next bar
				;
				; if we've looked at them all, we're done
				if pp ge npks-1 then begin
					done2 = (1 eq 1)
					done = (1 eq 1)
				endif
			endwhile
		endwhile
	endif
	;
	; check results
	if npks ne 60 then begin
		;
		; keep decrementing threshhold until we reach 60 peaks
		smul = (smul - 0.01) > 0.01
		;barth = rowmax*smul
		barth = rowmax*smul>skylim
		print,'tries, smul, barth, npks: ',tries,smul,barth,npks
	endif
	;
	; keep incrementing tries until we reach limit
	tries += 1
endwhile
ecwi_print_info,ppar,pre,'final bar thresh, ntries',barth,tries
;
; did we succeed?
if npks ne 60 then begin
	ecwi_print_info,ppar,pre,'unable to find 60 peaks',npks,/error
	plot,row>0.,/ys
	oplot,pks,fltarr(npks)+barth,psym=5
	q=''
	read,'next: ',q
	egeom.status=1
	return
endif
ecwi_print_info,ppar,pre,'Found 60 peaks'
;
; keep track of max values
pkmax = fltarr(npks)
;
; position arrays
peakx = fltarr(npts,npks) - 99.9
xi = fltarr(npts*npks)	; input x values
yi = fltarr(npts*npks)	; input y values
xo = fltarr(npts*npks)	; output x values
			; output y = input y
barx = fltarr(npks)	; canonical bar x positions
bar = intarr(npts*npks) - 9	; bar id for each point
slice = intarr(npts*npks) - 9	; slice id for each point
pp = 0L
;
; get starting positions from middle row
for j=0,npks-1 do begin
	;
	; get index range for this peak
	;st = sta[j]
	;
	; convert back into index list
	;rangepar,sta[j],x
	x = lindgen(12) + (fix(pks[j])-6)
	;
	; get fluxes in range
	y = row[x]
	;
	; centroid on this peak
	cnt=cntrd1d(x,y)
	;
	; re-center window based on centroid
	t0 = fix(cnt) - pbuf
	t1 = fix(cnt) + pbuf
	nx = (t1-t0)+1
	;
	; get x values
	x = t0 + indgen(nx)
	;
	; get fluxes in range
	y = row[x]
	;
	; re-centroid before fitting
	cnt=cntrd1d(x,y)
	;
	; choose a fit method (default is centroid)
	if keyword_set(gauss) or keyword_set(moffat) then begin
		;
		; x-vector for plotting
		xp = t0 + indgen(nx*100)/100.
		;
		; initial estimates to improve fitting success ratio
		est=[max(y),cnt,2.,1.]
		;
		; do fit
		yfit = mpfitpeak(x,y,a,nterms=nter,estimate=est,error=sqrt(y), $
			chisq=chi2,dof=dof,perror=sig,gauss=gauss,moffat=moffat)
		;
		; sometimes mpfitpeak just doesn't return this
		if n_elements(sig) le 0 then sig = (a-a)-99.
		;
		; reduced chi^2
		redchi = chi2/float(dof)
		;
		; generate moffat plot
		if keyword_set(moffat) then begin
			u = trace_u(xp,a)
			if nter ge 5 then f = a[4] else f = 0
			if nter ge 6 then f = f + a[5]*xp
			denom0 = (u^2 + 1)
			denom  = denom0^(-a[3])
			yp = f + a[0] * denom
		;
		; else generate gaussian plot
		endif else yp = gaussian(xp,a)
		;
		; derive yrange for plot
		yrng = [0.,max([yp,y,yfit])]*1.10
		;
		; store values
		barx[j] = a[1]
		pkmax[j] = a[0]
		peakx[p0,j] = a[1]
		xi[pp] = a[1]
		xo[pp] = a[1]
		;
		; print results
		ecwi_print_info,ppar,pre,'Pk#, chi^2/dof, GauPk, sig, Cntr',$
				j,redchi,a[1],sig[1],cnt, $
				format='(a,i3,4f8.2)',info=2
	;
	; do centroid instead of fitting
	endif else begin
		;
		; get y range for plotting
		yrng = [0.,max(y)]*1.10
		;
		; store values
		barx[j] = cnt
		pkmax[j] = max(y)
		peakx[p0,j] = cnt
		xi[pp] = cnt
		xo[pp] = cnt
		;
		; print results
		ecwi_print_info,ppar,pre,'Pk#, Cntr',j,cnt, $
				format='(a,i3,f8.2)',info=2
	endelse
	;
	; values independant of fitting method
	yi[pp] = y0
	bar[pp] = j
	slice[pp] = fix(j/5)
	pp += 1
	;
	; plot results
	if do_plots ge 2 then begin
		xrng = [min(x)-1,max(x)+1]
		plot,x,y,psym=-4,xran=xrng,/xsty,xtitle='PIX', $
			yran=yrng,/ysty,ytitle='INT', $
			charsi=1.5,symsi=1.5, $
			title = 'Image: '+strn(egeom.cbarsimgnum) + $
				', Middle Row - Bar: '+strn(j)+ $
				', Slice: '+strn(fix(j/5))
		;
		; over plot fit results if fitting done
		if keyword_set(gauss) or keyword_set(moffat) then begin
			oplot,xp,yp,linesty=5
			oplot,[a[1],a[1]],[-100,10000],linesty=5
		endif
		;
		; overplot centroid
		oplot,[cnt,cnt],[-100,10000]
		;
		; query user
		read,'Next? (Q-quit plotting, <cr>-next): ',q
		if strupcase(strmid(strtrim(q,2),0,1)) eq 'Q' then $
			do_plots = 0
	endif
endfor
print,pre+': Info - Done.'
;
; recover plot state
do_plots = ppar.display
;
; calculate reference output x control point positions
; assumes egeom.refbar is middle bar of slice (out of 5 bars per slice)
if egeom.refbar ge 0 and egeom.refbar lt 60 then $
	refb = egeom.refbar $
else	refb = 2	; default
delx = 0.
for i=1,4 do begin
	bb = (refb-2) + i
	delx = delx + barx[bb] - barx[bb-1]
endfor
delx = delx / 4.0
egeom.refdelx = delx
egeom.refoutx = barx[refb] + (findgen(5)-2.) * delx
;
; log results
ecwi_print_info,ppar,pre,'reference delta x',egeom.refdelx
ecwi_print_info,ppar,pre,'reference x positions',egeom.refoutx, $
	format='(a,5f9.2)'
;
; now trace each peak up and down
if do_plots ge 1 then begin
	;
	; plot control points over entire image
	xrng = [0,sz[0]]
	yrng = [0,sz[1]]
	;
	; start with middle row
	plot,peakx[p0,*],replicate(peaky[p0],npks), $
		xran=xrng,/xsty,xtitle='X PIX', $
		yran=yrng,/ysty,ytitle='Y PIX', $
		title='Image: '+strn(egeom.cbarsimgnum) + $
		', CBARS Input Geometry Control Points', $
		charsi=1.5,symsi=1.5,psym=7
endif
;
; trace both ways
msg = [ 'Tracing peaks in upper half of image...', $
	'Tracing peaks in lower half of image...' ]
inc = [1,-1]
off = [-1,1]
lim = [npts-1,0]
;
; loop over up,down
for k=0,1 do begin
    ecwi_print_info,ppar,pre,msg[k]
    ;
    ; loop over peaks
    for j=0,npks-1 do begin
	;
	; loop over samples
	for i=p0+inc[k],lim[k],inc[k] do begin
	    x0c = peakx[i+off[k],j]
	    ;
	    ; allow for skipping some bad fits
	    nskip = 1
	    while x0c lt 0 and nskip lt 3 do begin	; can only skip 3
		    nskip = nskip + 1
		    x0c = peakx[i+nskip*off[k],j]
	    endwhile
	    ;
	    ; make sure we have a good starting point
	    if x0c gt 0 then begin
		;
		; working row
		iy = peaky[i]
		row=reform(total(img[*,(iy-navg):(iy+navg)],2)/float(2*navg+1.))
		;
		; initial x range
		t0 = fix(x0c) - pbuf
		t1 = fix(x0c) + pbuf
		nx = (t1-t0)+1
		x = t0 + indgen(nx)
		;
		; get fluxes in range
		y = row[x]
		;
		; get centroid
		cnt=cntrd1d(x,y)
		;
		; re-do x range
		t0 = fix(cnt) - pbuf
		t1 = fix(cnt) + pbuf
		nx = (t1-t0)+1
		x = t0 + indgen(nx)
		;
		; update fluxes in range
		y = row[x]
		;
		; get updated centroid
		cnt=cntrd1d(x,y)
		;
		; do fitting if we are not centroiding
		if keyword_set(gauss) or keyword_set(moffat) then begin
			;
			; initial estimates to improve fitting success ratio
			est=[max(y),cnt,2.,1.]
			;
			; do fit
			yfit = mpfitpeak(x,y,a,nterms=nter,estimate=est, $ 
				error=sqrt(y),chisq=chi2,dof=dof,sigma=sig, $
				gauss=gauss,moffat=moffat)
			;
			; sometimes mfitpeak just doesn't return this
			if n_elements(sig) le 0 then sig = (a-a)-99.
			;
			; reduced chi^2 for testing
			redchi = chi2/float(dof)
			;
			; check fit
			if finite(redchi) eq 1 and redchi lt 199. and $
				redchi gt 0. and a[0] gt pkmax[j]*0.05 and $
				sig[1] lt 99. and sig[1] gt 0. and $
				abs(cnt-a[1]) lt 1.5 then begin
				if do_plots ge 1 then plots,a[1],iy,psym=1
				;
				; store values
				peakx[i,j] = a[1]
				xi[pp] = a[1]
				xo[pp] = peakx[p0,j]
			endif
			;
			; print results
			;ecwi_print_info,ppar,pre, $
			;	'Bar#,Sam#,chi^2/DOF,GauCnt,GauSig,Cnt,Pk', $
			;	j,i,redchi,a[1],sig[1],cnt,a[0], $
			;	format='(a,2i5,5f9.2)',info=2
		;
		; here we are just centroiding so no fitting
		endif else begin
			;
			; check centroid
			if abs(x0c - cnt) le 2.0 and $
			   max(y) gt pkmax[j]*0.05 then begin
				if do_plots ge 1 then plots,cnt,iy,psym=1
				;
				; store values
				peakx[i,j] = cnt
				xi[pp] = cnt
				xo[pp] = peakx[p0,j]
			endif
			;
			; print results
			;ecwi_print_info,ppar,pre,'Bar#,Sam#,Cnt,Max[y],Pk', $
			;	j,i,cnt,max(y),pkmax[j], $
			;	format='(a,2i5,3f9.2)',info=2
		endelse	; centroiding
		;
		; values independant of fitting method
		yi[pp] = iy
		bar[pp] = j
		slice[pp] = fix(j/5)
		pp += 1
	    endif	; x0c gt 0
	endfor	; looping over samples
    endfor	; looping over peaks
endfor	; loop over directions (up,down)
if do_plots ge 1 then begin
	oplot,!x.crange,[egeom.trimy0,egeom.trimy0],thick=3
	oplot,!x.crange,[egeom.trimy1,egeom.trimy1],thick=3
endif
print,pre+': Info - Done.'
;
; continue?
if do_plots ge 2 then $
	read,'Continue (<cr>): ',q
;
; yo is the same as yi
yo = yi
;
; call polywarp
polywarp,xi,yi,xo,yo,pdeg,fkx,fky,/double
;
; fill ECWI_GEOM struct
egeom.kx = fkx
egeom.ky = fky
egeom.xi = xi
egeom.yi = yi
egeom.xo = xo
egeom.yo = yo
egeom.bar = bar
egeom.slice = slice
egeom.barx = barx
egeom.midrow = midrow
egeom.initialized = 1
egeom.progid = pre
egeom.timestamp = systime(1)
;
; make warped version, if requested
warpim = poly_2d(img,fkx,fky,2,cubic=-0.5)
;
status = 0	; we're good!
return
end
