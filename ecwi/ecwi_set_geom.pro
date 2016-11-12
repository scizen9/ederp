;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_SET_GEOM
;
; PURPOSE:
;	This procedure uses the input ECWI_CFG struct to set the basic
;	parameters in the ECWI_GEOM struct.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_SET_GEOM, Egeom, Ecfg
;
; INPUTS:
;	Egeom	- Input ECWI_GEOM struct.
;	Ecfg	- Input ECWI_CFG struct for a given observation.
;	Ppar	- Input ECWI_PPAR struct.
;
; KEYWORDS:
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	Sets the following tags in the ECWI_GEOM struct according to the
;	configuration settings in ECWI_CFG.
;
; PROCEDURE:
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-AUG-13	Initial version
;	2014-AUG-14	Added CWI Yellow grating
;-
pro ecwi_set_geom,egeom,iecfg,ppar, help=help
	;
	; setup
	pre = 'ECWI_SET_GEOM'
	;
	; help request
	if keyword_set(help) then begin
		print,pre+': Info - Usage: '+pre+', Egeom, Ecfg, Ppar'
		return
	endif
	;
	; verify Egeom
	ksz = size(egeom)
	if ksz[2] eq 8 then begin
		if egeom.initialized ne 1 then begin
			print,pre+': Error - ECWI_GEOM struct not initialized.'
			return
		endif
	endif else begin
		print,pre+': Error - malformed ECWI_GEOM struct'
		return
	endelse
	;
	; verify Ecfg
	if ecwi_verify_cfg(iecfg,/silent) ne 0 then begin
		print,pre+': Error - malformed ECWI_CFG struct'
		return
	endif
	;
	; verify Ppar
	psz = size(ppar)
	if psz[2] eq 8 then begin
		if ppar.initialized ne 1 then begin
			print,pre+': Error - ECWI_PPAR struct not initialized.'
			return
		endif
	endif else begin
		print,pre+': Error - malformed ECWI_PPAR struct'
		return
	endelse
	;
	; take singleton of ECWI_CFG
	ecfg = iecfg[0]
	;
	; check image type
	if strtrim(strupcase(ecfg.imgtype),2) ne 'CBARS' then begin
		ecwi_print_info,ppar,pre,'cbars images are the geom reference files, this file is of type',ecfg.imgtype,/error
		return
	endif
	;
	; get output geom file name
	odir = ppar.reddir
	egeom.geomfile = ppar.reddir + $
	    strmid(ecfg.obsfname,0,strpos(ecfg.obsfname,'_int')) + '_geom.save'
    	;
    	; set basic configuration parameters
	egeom.gratid = ecfg.gratid
	egeom.gratnum = ecfg.gratnum
	egeom.filter = ecfg.filter
	egeom.filtnum = ecfg.filtnum
	egeom.campos = ecfg.campos
	egeom.gratpos = ecfg.gratpos
	egeom.gratanom = ecfg.gratanom
	egeom.xbinsize = ecfg.xbinsize
	egeom.ybinsize = ecfg.ybinsize
	egeom.nx = ecfg.naxis1
	egeom.ny = ecfg.naxis2
	egeom.x0out = 30 / egeom.xbinsize
	egeom.goody0 = 10
	egeom.goody1 = egeom.ny - 10
	egeom.trimy0 = 0
	egeom.trimy1 = egeom.ny
	egeom.ypad = 600
	egeom.nasmask = ecfg.nasmask
	if ecfg.nasmask eq 1 then begin
		egeom.goody0 = ecfg.nsobjr0 + 18
		egeom.goody1 = ecfg.nsobjr1 - 18
		egeom.trimy0 = ecfg.nsobjr0 - 18
		egeom.trimy1 = ecfg.nsobjr1 + 18
		egeom.ypad = 0
	endif
	;
	; get noise model
	rdnoise = 0.
	;
	; sum over amp inputs
	switch ecfg.nvidinp of
		4: rdnoise = rdnoise + ecfg.biasrn4
		3: rdnoise = rdnoise + ecfg.biasrn3
		2: rdnoise = rdnoise + ecfg.biasrn2
		1: rdnoise = rdnoise + ecfg.biasrn1
	endswitch
	;
	; take average
	rdnoise /= float(ecfg.nvidinp)
	egeom.rdnoise = rdnoise
	;
	; wavelength numbers default from header
	egeom.cwave = ecfg.cwave
	egeom.wave0out = ecfg.wave0	
	egeom.wave1out = ecfg.wave1
	egeom.dwout = ecfg.dwav
	;
	; reference spectrum
	egeom.refspec = ppar.datdir+ppar.atlas
	egeom.reflist = ppar.datdir+ppar.linelist
	egeom.refname = ppar.atlasname
	;
	; default to no cc offsets
	egeom.ccoff = fltarr(12)
	;
	; check for CWI data
    	if strtrim(strupcase(ecfg.instrume),2) eq 'CWI' or $
	   strtrim(strupcase(ecfg.instrume),2) eq 'ECWI' or $
	   strtrim(strupcase(ecfg.instrume),2) eq 'FCWI' or $
	   strtrim(strupcase(ecfg.instrume),2) eq 'PCWI' then begin
		;
		; check resolution and dispersion
		if strtrim(ecfg.gratid,2) eq 'RED' then begin
			egeom.resolution = 1.16	; Angstroms
			egeom.wavran = 740.	; Angstroms
			egeom.ccwn = 260./egeom.ybinsize	; Pixels
			egeom.rho = 2.1730d
			egeom.slant = -1.0d
			egeom.lastdegree = 4
			;
			; output disperison
			egeom.dwout = 0.11 * float(ecfg.ybinsize)
		endif else if strtrim(ecfg.gratid,2) eq 'YELLOW' then begin
			egeom.resolution = 0.82	; Angstroms
			egeom.wavran = 570	; Angstroms
			egeom.ccwn = 260./egeom.ybinsize	; Pixels
			egeom.rho = 2.5300d
			egeom.slant = -1.1d
			egeom.lastdegree = 4
			;
			; output disperison
			egeom.dwout = 0.137 * float(ecfg.ybinsize)
		endif else if strtrim(ecfg.gratid,2) eq 'BLUE' then begin
			egeom.resolution = 0.98	; Angstroms
			egeom.wavran = 440.	; Angstroms
			egeom.ccwn = 260./egeom.ybinsize	; Pixels
			egeom.rho = 3.050d
			egeom.slant = 0.50d
			egeom.lastdegree = 4
			;
			; output disperison
			egeom.dwout = 0.095 * float(ecfg.ybinsize)
		endif else if strtrim(ecfg.gratid,2) eq 'MEDREZ' then begin
			;
			; MEDREZ requires input offsets or bar-to-bar cc will fail
			;offs = [ 0., -355.,  -42., -385.,  -35., -400., $
			;	 -77., -440.,  -70., -484.,  -122., -635.]
			offs = [ -580, -130., -489.,  -74., -446.,  -83., $
				-408.,  -38., -385.,  -45.,  -355., 0.]
			egeom.ccoff = offs
			egeom.resolution = 2.50	; Angstroms
			egeom.wavran = 1310.	; Angstroms
			egeom.ccwn = 40./egeom.ybinsize	; Pixels
			egeom.rho = 1.20d
			egeom.slant = 0.0d
			egeom.lastdegree = 5
			;
			; output disperison
			egeom.dwout = 0.210 * float(ecfg.ybinsize)
		endif
		;
		; check central wavelength
		if egeom.cwave le 0. then $
			egeom.cwave = cwi_central_wave(strtrim(egeom.gratid,2),$
				ecfg.campos, ecfg.gratpos)
		;
		; spatial scales
		;egeom.pxscl = 0.00008096d0	; degrees per unbinned pixel
		egeom.pxscl = 0.000070165d0	; degrees per unbinned pixel
		egeom.slscl = 0.00075437d0	; degrees per slice
	;
	; check for KCWI data
	endif else if strtrim(strupcase(ecfg.instrume),2) eq 'KCWI' then begin
		;
		; check resolution and dispersion
		if strtrim(ecfg.gratid,2) eq 'BH1' then begin
			egeom.resolution = 0.25
			egeom.wavran = 120.
			egeom.ccwn = 260./egeom.ybinsize
			egeom.rho = 3.72d
			egeom.slant = -1.0d
			egeom.lastdegree = 4
			;
			; output disperison
			egeom.dwout = 0.095 * float(ecfg.ybinsize)
		endif
		;
		; spatial scales
		egeom.pxscl = 0.00004048d0	; deg/unbinned pixel
		egeom.slscl = 0.00037718d0	; deg/slice
		if ecfg.ifupos eq 2 then begin
			egeom.slscl = egeom.slscl/2.d0
		endif else if ecfg.ifupos eq 3 then begin
			egeom.slscl = egeom.slscl/4.d0
		endif
		;
		; check central wavelength
		if egeom.cwave le 0. then begin
			ecwi_print_info,ppar,pre,'No central wavelength found',/error
			return
		endif
	endif else begin
		ecwi_print_info,ppar,pre,'Unknown instrument',ecfg.instrume,/error
		return
	endelse
	;
	; now check ppar values which override defaults
	if ppar.dw gt 0. then $
		egeom.dwout = ppar.dw
	if ppar.wave0 gt 0. then $
		egeom.wave0out = ppar.wave0
	if ppar.wave1 gt 0. then $
		egeom.wave1out = ppar.wave1
	;
	; print log of values
	ecwi_print_info,ppar,pre,'Data cube output Disp (A/px), Wave0 (A): ', $
		egeom.dwout,egeom.wave0out,format='(a,f8.3,f9.2)'
	;
	; log our change of geom struct
	egeom.progid = pre
	egeom.timestamp = systime(1)
	;
	return
end
