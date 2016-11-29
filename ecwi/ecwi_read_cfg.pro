;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	ECWI_READ_CFG
;
; PURPOSE:
;	This function reads the header from a ECWI image file and returns
;	a ecwi_cfg structure.
;
; CATEGORY:
;	Data reduction for the EMCCD Cosmic Web Imager (ECWI).
;
; CALLING SEQUENCE:
;	Result = ECWI_READ_CFG( OBSFNAME )
;
; INPUTS:
;	obsfname- filename of ECWI image file
;
; KEYWORDS:
;	VERBOSE - set this to get extra screen output
;
; RETURNS:
;	ECWI CFG struct (as defined in ecwi_cfg__define.pro)
;
; PROCEDURE:
;	Reads in fits header and populates the ECWI_CFG struct.
;
; EXAMPLE:
;
;	This will read in the file 'm82.fits' and return a ecwi_cfg struct:
;
;	m82cfg = ECWI_READ_CFG('m82.fits')
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-MAY-03	Initial version
;	2014-SEP-12	Put in code to verify header
;-
function ecwi_read_cfg,obsfname,verbose=verbose
;
; initialize
	pre = 'ECWI_READ_CFG'
	A = {ecwi_cfg}		; get blank parameter struct
	cfg = struct_init(A)	; initialize it
;
; get filename if not passed as a parameter
	if n_params(0) lt 1 then begin
		obsfname = ''
		read,'Enter ECWI image FITS file name: ',obsfname
	endif
;
; check file
	fi = file_info(obsfname)
	if not fi.exists or not fi.read or not fi.regular then begin
		print,pre+': Error - file not accessible: ',obsfname
		return,cfg
	endif
;
; read header of ECWI image FITS file
	hdr = headfits(obsfname)
;
; verify header
	if size(hdr,/type) ne 7 or size(hdr,/dim) le 10 then begin
		print,pre+': Error - bad header: ',obsfname
		return,cfg
	endif
;
; get parameter struct tags
	keys = tag_names(cfg)
	nkeys = n_elements(keys)
	stopky = where(strcmp(keys,'JULIANDATE') eq 1)>0<nkeys
	stopky = stopky[0]
;
; get values for all native property keys
	for j=0, stopky-1 do $
		cfg.(j) = sxpar(hdr,keys[j])
;
; process the derived property keys
	ccdsum		= sxpar(hdr,'CCDSUM')
	cfg.xbinsize	= fix(gettok(ccdsum,' '))
	cfg.ybinsize	= fix(ccdsum)
	if cfg.xbinsize gt 1 or cfg.ybinsize gt 1 then $
		cfg.binning	= 1 $
	else	cfg.binning	= 0
	cfg.juliandate	= ecwi_parse_dates(cfg.date)
	fdecomp,obsfname,disk,dir,root,ext
	cfg.obsfname	= root + '.' + ext
	cfg.obsdir	= disk + dir
	cfg.obstype	= 'test'
	if strpos(cfg.imgtype,'bias') ge 0 or $
	   strpos(cfg.imgtype,'dark') ge 0 then cfg.obstype = 'zero'
   	if strpos(cfg.imgtype,'arc') ge 0 or $
	   strpos(cfg.imgtype,'bars') ge 0 or $
	   strpos(cfg.imgtype,'flat') ge 0 then cfg.obstype = 'cal'
   	if strpos(cfg.imgtype,'object') ge 0 then cfg.obstype = 'obj'
	if cfg.juliandate le 0 then begin
		cfg.obstype = 'test'
		cfg.imgtype = 'test'
	endif
	cfg.imgnum	= long(stregex(root,'[0-9]+',/extract))
	cfg.initialized	= 1
	cfg.timestamp	= double(fi.mtime)	; use file timestamp
	return,cfg
end
