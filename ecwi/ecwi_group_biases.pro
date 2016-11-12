;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_GROUP_BIASES
;
; PURPOSE:
;	This procedure groups biases in the ECWI_CFG struct for a given night.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_GROUP_BIASES, Ecfg, Ppar, Bcfg
;
; INPUTS:
;	Ecfg	- array of struct ECWI_CFG for a given directory
;	Ppar	- ECWI_PPAR pipeline parameter struct
;
; OUTPUTS:
;	Bcfg	- a ECWI_CFG struct vector with one entry for each bias group
;
; KEYWORDS:
;
; SIDE EFFECTS:
;	Outputs pipeline parameter file in ODIR for each bias group.
;
; PROCEDURE:
;	Finds bias images by inspecting the imgtype tags in Ecfg and
;	groups contiguous bias images.  Returns a ECWI_CFG struct vector
;	with one element for each bias group which is used to associate 
;	the bias groups with other observations.
;
; EXAMPLE:
;	Group bias images from directory 'night1/' and put the resulting
;	ppar files in 'night1/redux/':
;
;	KCFG = ECWI_READ_CFGS('night1/')
;	ECWI_GROUP_BIASES, KCFG, PPAR, BCFG
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-MAY-03	Initial version
;	2013-SEP-09	Added loglun keyword
;	2013-SEP-13	Now use ECWI_PPAR struct for parameters
;-
pro ecwi_group_biases, ecfg, ppar, bcfg
	;
	; setup
	pre = 'ECWI_GROUP_BIASES'
	;
	; instantiate and init a ECWI_CFG struct for the bias groups
	B = {ecwi_cfg}
	bcfg = struct_init(B)
	;
	; check inputs
	if ecwi_verify_cfg(ecfg) ne 0 then return
	if ecwi_verify_ppar(ppar) ne 0 then return
	;
	; get bias list
	biases = where(strpos(ecfg.imgtype,'bias') ge 0, nbiases)
	;
	; if we have biases, group them
	if nbiases gt 0 then begin
		;
		; create range list of all biases
		rangepar,biases,blist
		;
		; get bias groups split by comma
		bgroups = strsplit(blist,',',/extract,count=ngroups)
		;
		; record number of groups
		ppar.nbgrps = ngroups
		ppar.biasexists = 1
		;
		; setup ECWI_CFG struct for groups
		bcfg = replicate(bcfg, ngroups)
		;
		; loop over bias groups
		g = 0	; good group counter
		for i=0,ngroups-1 do begin
			;
			; fresh copy of ECWI_PPAR struct
			pp = ppar
			;
			; get image numbers for this group
			rangepar,bgroups[i],blist
			nims = n_elements(blist)
			;
			; check if skip1 set
			if pp.biasskip1 ne 0 and nims gt 1 then begin
				blist = blist[1:*]
				nims = n_elements(blist)
			endif
			;
			; do we have enough for a group?
			if nims ge pp.mingroupbias then begin
				imnums = ecfg[blist].imgnum
				rangepar,imnums,rl
				pp.biases		= rl
				bcfg[g].grouplist	= rl
				bcfg[g].nimages		= nims
				;
				; get date from first bias in series
				b = blist[0]
				bcfg[g].juliandate	= ecfg[b].juliandate
				bcfg[g].date		= ecfg[b].date
				;
				; configuration
				bcfg[g].imgtype		= 'bias'
				bcfg[g].naxis		= ecfg[b].naxis
				bcfg[g].naxis1		= ecfg[b].naxis1
				bcfg[g].naxis2		= ecfg[b].naxis2
				bcfg[g].binning		= ecfg[b].binning
				bcfg[g].xbinsize	= ecfg[b].xbinsize
				bcfg[g].ybinsize	= ecfg[b].ybinsize
				;
				; use first image number in group
				gi = ecfg[b].imgnum
				;
				; files and directories
				pp.masterbias		= 'mbias_' + $
					string(gi,'(i0'+strn(pp.fdigits)+')') +$
								'.fits'
				pp.ppfname		= 'mbias_' + $
					string(gi,'(i0'+strn(pp.fdigits)+')') +$
								'.ppar'
				bcfg[g].groupnum	= gi
				bcfg[g].groupfile	= pp.masterbias
				bcfg[g].grouppar	= pp.ppfname
				;
				; status
				pp.initialized		= 1
				pp.progid		= pre
				bcfg[g].initialized	= 1
				;
				; write out ppar file
				ecwi_write_ppar,pp
				;
				; increment group counter
				g = g + 1
			endif	; do we have enough images?
		endfor	; loop over bias groups
		;
		; all groups failed
		if g le 0 then begin
			;
			; return an uninitialized, single ECWI_CFG struct
			bcfg = bcfg[0]
			ppar.biasexists = 0
			ecwi_print_info,ppar,pre,'no bias groups with >= ', $
				ppar.mingroupbias, ' images.',/warning
		;
		; some groups failed
		endif else if g lt ngroups then begin
			;
			; trim ECWI_CFG struct to only good groups
			bcfg = bcfg[0:(g-1)]
			ecwi_print_info,ppar,pre,'removing ', ngroups - g, $
				' bias groups with < ', ppar.mingroupbias, $
				' images.', format='(a,i3,a,i3,a)'
		endif	; otherwise, we are OK as is
		;
		; update number of groups
		ppar.nbgrps = g
	;
	; no bias frames found
	endif else $
		ecwi_print_info,ppar,pre,'no bias frames found',/warning
	;
	return
end
