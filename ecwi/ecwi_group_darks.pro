;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_GROUP_DARKS
;
; PURPOSE:
;	This procedure groups biases in the ECWI_CFG struct for a given night.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_GROUP_DARKS, Ecfg, Ppar, Dcfg
;
; INPUTS:
;	Ecfg	- array of struct ECWI_CFG for a given night
;	Ppar	- ECWI_PPAR pipeline parameter struct
;
; OUTPUTS:
;	Dcfg	- array of struct ECWI_CFG, one for each dark group
;
; KEYWORDS:
;
; SIDE EFFECTS:
;	Outputs pipeline parameter file in ODIR for each dark group.
;
; PROCEDURE:
;	Finds dark images by inspecting the imgtype tags in Ecfg and
;	gropus contiguous dark images.  Returns a ECWI_CFG struct vector
;	with one element for each dark group which is used to associate 
;	the dark groups with other observations.
;
; EXAMPLE:
;	Group dark images from directory 'night1/' and put the resulting
;	ppar files in 'night1/redux/':
;
;	KCFG = ECWI_NIGHT_READ('night1/')
;	ECWI_GROUP_DARKS, KCFG, PPAR, DCFG
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-MAY-03	Initial version
;	2013-SEP-09	Added loglun keyword
;	2013-SEP-13	Now use ECWI_PPAR struct for parameters
;-
pro ecwi_group_darks, ecfg, ppar, dcfg
	;
	; setup
	pre = 'ECWI_GROUP_DARKS'
	;
	; instantiate and init a ECWI_CFG struct for the dark groups
	D = {ecwi_cfg}
	dcfg = struct_init(D)
	;
	; check inputs
	if ecwi_verify_cfg(ecfg) ne 0 then return
	if ecwi_verify_ppar(ppar) ne 0 then return
	;
	; get dark list
	darks = where(strmatch(ecfg.imgtype,'dark') eq 1, ndarks)
	;
	; if we have darks, group them
	if ndarks gt 0 then begin
		;
		; create range list of all darks
		rangepar,darks,dlist
		;
		; get dark groups split by comma
		dgroups = strsplit(dlist,',',/extract,count=ngroups)
		;
		; record number of groups
		ppar.ndgrps = ngroups
		ppar.darkexists = 1
		;
		; setup ECWI_CFG struct for groups
		dcfg = replicate(dcfg, ngroups)
		;
		; loop over dark groups
		g = 0	; good group counter
		for i=0,ngroups-1 do begin
			;
			; fresh copy of ECWI_PPAR struct
			pp = ppar
			;
			; get image numbers for this group
			rangepar,dgroups[i],dlist
			nims = n_elements(dlist)
			;
			; do we have enough for a group?
			if nims ge pp.mingroupdark then begin
				imnums = ecfg[dlist].imgnum
				rangepar,imnums,rl
				pp.darks		= rl
				dcfg[g].grouplist	= rl
				dcfg[g].nimages		= nims
				;
				; get date from first dark in series
				d = dlist[0]
				dcfg[g].juliandate	= ecfg[d].juliandate
				dcfg[g].date		= ecfg[d].date
				;
				; configuration
				dcfg[g].imgtype		= 'dark'
				dcfg[g].naxis		= ecfg[d].naxis
				dcfg[g].naxis1		= ecfg[d].naxis1
				dcfg[g].naxis2		= ecfg[d].naxis2
				dcfg[g].binning		= ecfg[d].binning
				dcfg[g].xbinsize	= ecfg[d].xbinsize
				dcfg[g].ybinsize	= ecfg[d].ybinsize
				;
				; use first image number in group
				gi = ecfg[d].imgnum
				;
				; files and directories
				pp.masterdark		= 'mdark_' + $
					string(gi,'(i0'+strn(pp.fdigits)+')') +$
								'.fits'
				pp.ppfname		= 'mdark_' + $
					string(gi,'(i0'+strn(pp.fdigits)+')') +$
								'.ppar'
				;
				dcfg[g].groupnum	= gi
				dcfg[g].groupfile	= pp.masterdark
				dcfg[g].grouppar	= pp.ppfname
				;
				; status
				pp.initialized		= 1
				pp.progid		= pre
				dcfg[g].initialized	= 1
				;
				; write out ppar file
				ecwi_write_ppar,pp
				;
				; increment group counter
				g = g + 1
			endif	; do we have enough images?
		endfor	; loop over dark groups
		;
		; all groups failed
		if g le 0 then begin
			;
			; return an uninitialized, single ECWI_CFG struct
			dcfg = dcfg[0]
			ppar.darkexists = 0
			ecwi_print_info,ppar,pre,'no dark groups with >= ', $
				ppar.mingroupdark, ' images.',/warning
		;
		; some groups failed
		endif else if g lt ngroups then begin
			;
			; trim ECWI_CFG struct to only good groups
			dcfg = dcfg[0:(g-1)]
			ecwi_print_info,ppar,pre,'removing ', ngroups - g, $
				' dark groups with < ', ppar.mingroupdark, $
				' images.', format='(a,i3,a,i3,a)'
		endif	; otherwise, we are OK as is
		;
		; update number of grouops
		ppar.ndgrps = g
	;
	; no dark frames found
	endif else $
		ecwi_print_info,ppar,pre,'no dark frames found',/warning
	;
	return
end
