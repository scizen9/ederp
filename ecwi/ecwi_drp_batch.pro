;
; Copyright (c) 2014, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_DRP_BATCH
;
; PURPOSE:
;	This procedure will run the pipeline in batch mode.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	ECWI_DRP_BATCH, DirList
;
; INPUTS:
;	DirList	- list of run directories (string array)
;
; KEYWORDS:
;	DARK		- set to run ECWI_STAGE2DARK (def: NO)
;	CWI		- set to skip first bias and use CWI associations(def: NO)
;	MINOSCANPIX	- set to minimum pixels required for overscan subtraction
;	LASTSTAGE	- set to the last stage you want run
;	ONESTAGE	- set to a single stage you want run (overrides LASTSTAGE)
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	Runs pipeline in each directory specified in DirList.
;
; EXAMPLE:
;	ECWI_DRP_BATCH,['140527','140528','140529'],/cwi
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2014-JUN-03	Initial version
;	2014-OCT-23	Added onestage keyword
;	2014-NOV-07	Added stage7std to nominal run
;-
pro ecwi_drp_batch,dirlist,dark=dark,cwi=cwi, $
	minoscanpix=minoscanpix, $
	laststage=laststage, $
	onestage=onestage
;
; check keywords
if keyword_set(laststage) then $
	last = laststage $
else	last = 7
;
if keyword_set(onestage) then $
	one = onestage $
else	one = 0
;
; how many directories?
ndir = n_elements(dirlist)
;
; get defaults from ECWI_PPAR struct
A = {ecwi_ppar}
ppar = struct_init(A)
;
; loop over directories
for i=0,ndir-1 do begin
	cd,dirlist[i]
	print,dirlist[i]
	;
	; check for one stage
	if one gt 0 then begin
		case one of
			1: ecwi_stage1
			2: ecwi_stage2dark
			3: ecwi_stage3flat
			4: ecwi_stage4geom
			5: ecwi_stage5prof
			6: ecwi_stage6rr
			7: ecwi_stage7std
			else: print,'Illegal stage: ',one
		endcase
	;
	; otherwise run up to last stage
	endif else begin
		;
		; archive any existing output directory
		filestamp,ppar.reddir,/verbose
		;
		; make a new output directory
		spawn,'mkdir '+ppar.reddir
		;
		; get the pipeline ready
		ecwi_prep,cwi=cwi,/verbose,/display,minoscanpix=minoscanpix
		;
		; do basic ccd image reduction
		ecwi_stage1
		if last le 1 then goto,done
		;
		; if requested do dark subtraction
		if keyword_set(dark) then $
			ecwi_stage2dark
		if last le 2 then goto,done
		;
		; do flat field correction
		ecwi_stage3flat
		if last le 3 then goto,done
		;
		; solve for wavelengths and geometry
		ecwi_stage4geom
		if last le 4 then goto,done
		;
		; do slice profile correction
		ecwi_stage5prof
		if last le 5 then goto,done
		;
		; do relative response correction
		ecwi_stage6rr
		if last le 6 then goto,done
		;
		; do standard star calibration
		ecwi_stage7std
		;
		; done
		done:
	endelse
	;
	; return to where we started
	cd,'..'
endfor	; loop over directories
;
return
end
