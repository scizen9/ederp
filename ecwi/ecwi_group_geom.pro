;
; Copyright (c) 2014, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_GROUP_GEOM
;
; PURPOSE:
;	This procedure groups continuum bars (cbars) and arcs in the ECWI_CFG 
;	struct for a given night.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_GROUP_GEOM, Ecfg, Ppar, Ccfg, Acfg, Ngeom
;
; INPUTS:
;	Ecfg	- array of struct ECWI_CFG for a given directory
;	Ppar	- ECWI_PPAR pipeline parameter struct
;
; OUTPUTS:
;	Ccfg	- a ECWI_CFG struct vector with one entry for each cbars from
;			a calibration set
;	Acfg	- a ECWI_CFG struct vector with one entry for each arc from
;			a calibration set
;	Ngeom	- number of good geometry calibration groups
;
; KEYWORDS:
;
; SIDE EFFECTS:
;	None.
;
; PROCEDURE:
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2014-APR-01	Initial version
;-
pro ecwi_group_geom, ecfg, ppar, ccfg, acfg, ngeom
	;
	; setup
	pre = 'ECWI_GROUP_GEOM'
	;
	; check input
	if ecwi_verify_cfg(ecfg) ne 0 then return
	if ecwi_verify_ppar(ppar) ne 0 then return
	;
	; get size of ecfg
	ncfg = n_elements(ecfg)
	;
	; calibration groups
	cg = where(ecfg.obstype eq 'cal', ncal)
	;
	; set up for group counting
	ngeom = 0
	maxgrps = 100
	maxmemb = 50
	groups = lonarr(maxgrps,maxmemb) - 1l
	gind = 0
	p = 0
	;
	; set up first group
	gcfg = ecfg[cg[0]]
	groups[gind,p] = cg[0]
	p += 1
	;
	; loop over cal images and gather groups
	for i=1,ncal-1 do begin
		;
		; check configuration
		tcfg = ecwi_match_cfg(ecfg[cg[i]],gcfg,ppar,count=nm,/silent)
		;
		; check for sequential image numbers
		if ecfg[cg[i]].imgnum - gcfg.imgnum ne 1 or nm ne 1 then begin
			;
			; new group
			gind += 1
			p = 0
			;
			; check for group overflow
			if gind ge maxgrps then begin
				ecwi_print_info,'geom group overflow',gind,/error
				return
			endif
			;
			; first member of group
			gcfg = ecfg[cg[i]]
			groups[gind,p] = cg[i]
			p += 1
			;
			; check for member overflow
			if p ge maxmemb then begin
				ecwi_print_info,'geom group member overflow',p,/error
				return
			endif
		endif else begin
			;
			; next member of group
			gcfg = ecfg[cg[i]]
			groups[gind,p] = cg[i]
			p += 1
			;
			; check for member overflow
			if p ge maxmemb then begin
				ecwi_print_info,'geom group member overflow',p,/error
				return
			endif
		endelse
	endfor
	;
	; number of groups
	ngeom = gind + 1
	;
	; we'll check the status of each group
	stat = intarr(ngeom)
	;
	; here's where we collect arc and cbars indices
	ari = lonarr(ngeom) - 1l
	cbi = lonarr(ngeom) - 1l
	;
	; loop over groups
	for i=0,ngeom-1 do begin
		;
		; get indexes for this group
		igrp = reform(groups[i,*])
		good = where(igrp ge 0, nmem)
		igrp = igrp[good]
		;
		; look for arc/cbars nearest pair
		arci = -1l
		cbri = -1l
		for j=0,nmem-1 do begin
			;
			; collect each arc and cbars image in the group
			if strtrim(ecfg[igrp[j]].imgtype,2) eq 'arc' then $
				arci = [arci, igrp[j]]
			if strtrim(ecfg[igrp[j]].imgtype,2) eq 'cbars' then $
				cbri = [cbri, igrp[j]]
		endfor
		;
		; how many do we have?
		ga = where(arci ge 0, nga)
		gc = where(cbri ge 0, ngc)
		;
		; do we have enough?
		if nga gt 0 and ngc gt 0 then begin
			cbri = cbri[gc]
			arci = arci[ga]
			;
			; now find closest pair
			cbrimn = ecfg[cbri].imgnum
			arcimn = ecfg[arci].imgnum
			;
			one_cbr = intarr(ngc) + 1
			one_arc = intarr(nga) + 1
			diff = abs( (arcimn##one_cbr) - (one_arc##cbrimn))
			;
			match = (where(diff eq min(diff)))[0]
			ind = array_indices(diff,match)
			;
			cbi[i] = cbri[ind[0]]
			ari[i] = arci[ind[1<(n_elements(ind)-1)]]
			stat[i] = 1
		endif
	endfor
	;
	; get the good ones
	good = where(stat eq 1, ngeom)
	;
	; collect the good calibs
	if ngeom gt 0 then begin
		;
		; arcs
		acfg = ecfg[ari[good]]
		;
		; cbars
		ccfg = ecfg[cbi[good]]
	endif else begin
		acfg = -1
		ccfg = -1
		ecwi_print_info,ppar,pre,'no geom frame sets found',/warning
	endelse
	;
	; record results
	ppar.ncbars = ngeom
	ppar.narcs = ngeom
	if ngeom gt 0 then ppar.geomexists = 1
	;
	return
end
