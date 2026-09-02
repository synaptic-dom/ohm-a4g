Id rid = OhmAuditController.startAudit();
OhmDTO.AuditReadoutDTO d = OhmAuditController.getAuditStatus(rid);
Integer nf = (d.findings == null) ? 0 : d.findings.size();
System.debug('OHM_W3 grade=' + d.efficiencyGrade + ' score=' + d.efficiencyScore + ' findings=' + nf + ' energyCentral=' + d.orgEnergyWhCentral);
