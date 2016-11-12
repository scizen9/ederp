;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_GROUP_FLATS
;
; PURPOSE:
;	This procedure groups flats in the ECWI_CFG struct for a given night.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_GROUP_FLATS, Ecfg, Ppar, Fcfg
;
; INPUTS:
;	Ecfg	- array of struct ECWI_CFG for a given directory
;	Ppar	- ECWI_PPAR pipeline parameter struct
;
; OUTPUTS:
;	Fcfg	- a ECWI_CFG struct vector with one entry for each flat group
;
; KEYWORDS:
;
; SIDE EFFECTS:
;	Outputs pipeline parameter file in ODIR for each flat group.
;
; PROCEDURE:
;	Finds flat images by inspecting the imgtype tags in Ecfg and
;	groups contiguous flat images.  Returns a ECWI_CFG struct vector
;	with one element for each flat group which is used to associate 
;	the flat groups with other observations.
;
; EXAMPLE:
;	Group flat images from directory 'night1/' and put the resulting
;	ppar files in 'night1/redux/':
;
;	KCFG = ECWI_READ_CFGS('night1/')
;	ECWI_GROUP_FLATS, KCFG, PPAR, FCFG
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-AUG-29	Initial version
;	2013-SEP-09	Added loglun keyword
;	2013-SEP-13	Now use ECWI_PPAR struct for parameters
;-
pro ecwi_group_flats, ecfg, ppar, fcfg
	;
	; setup
	pre = 'ECWI_GROUP_FLATS'
	;
	; instantiate and init a ECWI_CFG struct for the flat groups
	F = {ecwi_cfg}
	fcfg = struct_init(F)
	;
	; check input
	if ecwi_verify_cfg(ecfg) ne 0 then return
	if ecwi_verify_ppar(ppar) ne 0 then return
	;
	; get flat list
	flats = where(strpos(ecfg.imgtype,'cflat') ge 0, nflats)
	;
	; if we have flats, group them
	if nflats gt 0 then begin
		;
		; create range list of all flats
		rangepar,flats,flist
		;
		; get flat groups split by comma
		fgroups = strsplit(flist,',',/extract,count=ngroups)
		;
		; record number of groups
		ppar.nfgrps = ngroups
		ppar.flatexists = 1
		;
		; setup ECWI_CFG struct for groups
		fcfg = replicate(fcfg, ngroups)
		;
		; loop over flat groups
		for i=0,ngroups-1 do begin
			;
			; fresh copy of ECWI_PPAR struct
			pp = ppar
			;
			; get image numbers for this group
			rangepar,fgroups[i],flist
			nims = n_elements(flist)
			imnums = ecfg[flist].imgnum
			rangepar,imnums,rl
			;
			; set parameters
			pp.cflats		= rl
			fcfg[i].grouplist	= rl
			fcfg[i].nimages		= nims
			;
			; get date and coords from first flat in series
			f = flist[0]
			fcfg[i].juliandate	= ecfg[f].juliandate
			fcfg[i].date		= ecfg[f].date
			fcfg[i].ra		= ecfg[f].ra
			fcfg[i].dec		= ecfg[f].dec
			;
			; configuration
			fcfg[i].imgtype		= 'cflat'
			fcfg[i].naxis		= ecfg[f].naxis
			fcfg[i].naxis1		= ecfg[f].naxis1
			fcfg[i].naxis2		= ecfg[f].naxis2
			fcfg[i].binning		= ecfg[f].binning
			fcfg[i].xbinsize	= ecfg[f].xbinsize
			fcfg[i].ybinsize	= ecfg[f].ybinsize
			fcfg[i].ampmode		= ecfg[f].ampmode
			fcfg[i].nasmask		= ecfg[f].nasmask
			fcfg[i].gratid		= ecfg[f].gratid
			fcfg[i].gratpos		= ecfg[f].gratpos
			fcfg[i].filter		= ecfg[f].filter
			fcfg[i].fm4pos		= ecfg[f].fm4pos
			fcfg[i].campos		= ecfg[f].campos
			fcfg[i].focpos		= ecfg[f].focpos
			;
			; use first image number in group
			fi = ecfg[f].imgnum
			;
			; files and directories
			pp.masterflat		= 'mflat_' + $
				string(fi,'(i0'+strn(pp.fdigits)+')') + '.fits'
			pp.ppfname		= 'mflat_' + $
				string(fi,'(i0'+strn(pp.fdigits)+')') + '.ppar'
			;
			fcfg[i].groupnum	= fi
			fcfg[i].groupfile	= pp.masterflat
			fcfg[i].grouppar	= pp.ppfname
			;
			; status
			pp.initialized		= 1
			pp.progid		= pre
			fcfg[i].initialized	= 1
			;
			; write out ppar file
			ecwi_write_ppar,pp
		endfor	; loop over flat groups
	endif else $
		ecwi_print_info,ppar,pre,'no flat frames found',/warning
	;
	return
end
