;
; Copyright (c) 2014, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_FIND_STDS
;
; PURPOSE:
;	This function finds the standard star observations within
;	the input configuration structure.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	Result = ECWI_FIND_STDS( Ecfg,  Ppar, Nstds)
;
; INPUTS:
;	Ecfg	- ECWI_CFG struct array
;	Ppar	- ECWI_PPAR pipeline parameter struct
;
; OUTPUTS:
;	Nstds	- How many standard star observations were found?
;
; RETURNS:
;	The indices of the observations within Ecfg that are standard star
;	observations.
;
; SIDE EFFECTS:
;	None.
;
; KEYWORDS:
;	None
;
; PROCEDURE:
;	Gets a list of standard star reference spectra in !ECWI_DATA directory
;	and compares the names to the object names in Ecfg configuration
;	struct to determine which are standard star observations.
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2014-NOV-05	Initial Revision
;-
function ecwi_find_stds,ecfg,ppar,nstds
	;
	; setup
	pre = 'ECWI_FIND_STDS'
	q=''
	nstds = 0
	stds = -1
	;
	; check inputs
	if ecwi_verify_cfg(ecfg,/init) ne 0 then return,stds
	if ecwi_verify_ppar(ppar,/init) ne 0 then return,stds
	;
	; log
	ecwi_print_info,ppar,pre,systime(0)
	;
	; directories
	if ecwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir) ne 0 then begin
		ecwi_print_info,ppar,pre,'Directory error, returning',/error
		return,stds
	endif
	;
	; test standard star directory
	if file_test(ddir+'stds',/directory,/read) ne 1 then begin
		ecwi_print_info,ppar,pre,'Standard star reference dir inaccessable, returning',/error
		return,stds
	endif
	;
	; get list of standard star reference spectra
	reflist = file_search(ddir+'stds/*.fit*',count=nrefs)
	;
	; get names from file names
	for i=0,nrefs-1 do begin
		fdecomp,reflist[i],disk,dir,name,ext
		reflist[i] = name
	endfor
	;
	; get observation names
	obnames = strlowcase(strtrim(ecfg.object,2))
	obstat = strcmp(strtrim(ecfg.imgtype,2),'object')
	;
	; set up a status array
	stdstat = intarr(n_elements(ecfg))
	;
	; loop over reference list
	for i=0,nrefs-1 do begin
		t = where(obstat eq 1 and strcmp(obnames,reflist[i]) eq 1, nt)
		if nt gt 0 then stdstat[t] = 1
	endfor
	;
	; get the standards, if any
	stds = where(stdstat eq 1, nstds)
	;
	; log results
	ecwi_print_info,ppar,pre,'Found this many standard star observations', $
		nstds,form='(a,i4)'
	;
	return,stds
end	; ecwi_find_stds
