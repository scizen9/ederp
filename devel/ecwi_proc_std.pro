;	copyright 2015 California Institute of Technology
;+
; ecwi_proc_std - process an Oke and Gunn stds table in AB mags
;
; inputs:
;	ifil	- Oke & Gunn std table in milli-Jy versus Ang.
; keywords:
;	eso	- set if from eso web site
;	display	- set to plot flam
;-
pro ecwi_proc_std,ifil,eso=eso,display=display
	;
	; setup
	pre = 'ECWI_PROC_STD'
	q=''
	;
	; are we an eso spectrum file?
	if keyword_set(eso) then begin
		;
		; check input file
		if file_test(ifil,/read) then begin
			readcol,ifil,w,flm,fjy,comment='*',format='f,f,f',/si
		endif else begin
			print,pre+' Error - file not found: ',ifil
			return
		endelse
		print,pre+': Warning - using default FWHM(A): 20.'
		fwhm = 20.
		flux  = flm * 1.e-16
	endif else begin
		;
		; get input units
		spawn,'grep UNITS '+ifil,output
		if strpos(output,'micro') ge 0 then begin
			tojan = 1000000.
		endif else begin
			tojan = 1000.
		endelse
		;
		; check input file
		if file_test(ifil,/read) then begin
			readcol,ifil,w,fjy,comment='*',format='f,f',/si
		endif else begin
			print,pre+' Error - file not found: ',ifil
			return
		endelse
		;
		; get bandwidth
		spawn,'grep BANDWIDTH '+ifil,res,err
		if strlen(err) le 0 and strlen(res) gt 0 then begin
			for i=0,3 do out=gettok(res,' ')
			fwhm = float(out)
			print,pre+': Info - using FWHM(A): ',fwhm,format='(a,f5.1)'
		endif else begin
			print,pre+': Warning - using default FWHM(A): 20.'
			fwhm = 20.
		endelse
		;
		fjy   = fjy/tojan				; to Jy
		flux  = fjy * 2.994e-5 / w^2			; convert to Flam
	endelse
	fwhms = replicate(fwhm,n_elements(w))		; FWHM
	;
	; check output file
	ofil = strmid(ifil,0,strpos(ifil,'.')) + '.fits'
	if file_test(ofil) then begin
		print,pre+': Error - file exists: ',ofil
	endif else begin
		A = { wavelength: 0., flux: 0., staterror: 0., $
			syserror: 0., fwhm: 0. }
		std = replicate(A, n_elements(w))
		std.wavelength	= w
		std.flux	= flux
		std.staterror	= flux*0.05
		std.syserror	= flux*0.05
		std.fwhm	= fwhms
		;
		; make header
		sxaddpar,hdr,'COMMENT','  '+pre
		sxaddpar,hdr,'COMMENT','  PROCESSING: '+ifil+' on '+systime(0)
		;
		; write out file
		mwrfits,std,ofil,hdr,/create
		print,'wrote: ',ofil
	endelse
	;
	if keyword_set(display) then begin
		deepcolor
		!p.background=colordex('white')
		!p.color=colordex('black')
		font_store=!p.font
		!p.font=1
		th=3
		si=2.
		;
		plot,w,alog10(flux),title=ifil,charsi=si,charthi=th, $
			xtitle='WAVE(A)', xtickformat='(f7.1)', $
			ytitle='Flam'
		!p.font=font_store
	endif
	;
end
