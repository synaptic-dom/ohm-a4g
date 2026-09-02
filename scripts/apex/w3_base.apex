Id rid = OhmAuditController.startAudit();
OhmDTO.AuditReadoutDTO d = OhmAuditController.getAuditStatus(rid);
System.debug('OHM_W3_BASE grade='+d.efficiencyGrade+' score='+d.efficiencyScore+' findings='+(d.findings==null?0:d.findings.size())+' energyCentral='+d.orgEnergyWhCentral);
