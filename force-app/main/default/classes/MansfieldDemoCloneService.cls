public with sharing class MansfieldDemoCloneService {
    // Developer note:
    // One-time Mansfield demo data loader with idempotent markers to prevent duplicate clones.
    public class RunResult {
        public Boolean dryRun;
        public Boolean success;
        public List<String> info = new List<String>();
        public List<String> warnings = new List<String>();
        public List<String> errors = new List<String>();
        public Map<String, String> markerStrategyByObject = new Map<String, String>();
        public Map<String, Integer> insertedByObject = new Map<String, Integer>();
        public Map<String, Integer> reusedByObject = new Map<String, Integer>();
    }

    private static final String RUN_NAMESPACE = 'MANSFIELD_DEMO';
    private static final String HIDDEN_MARKER_FIELD = 'analyticsdemo_batch_id__c';
    private static final Integer DML_CHUNK_SIZE = 200;

    private static final List<String> OBJECTS_IN_SCOPE = new List<String>{
        'Account',
        'Contact',
        'Site__c',
        'Opportunity',
        'outfunds__Funding_Request__c',
        'Additional_Fund__c',
        'Background_Check__c',
        'Task'
    };

    private static final List<String> REQUIRED_SITE_FIELDS = new List<String>{
        'Street_Address__c', 'City__c', 'State__c', 'Postal_Zip_Code__c',
        'Latitude__c', 'Longitude__c', 'Verified_Latitude__c', 'Verified_Longitude__c',
        'Site_Geolocation__Latitude__s', 'Site_Geolocation__Longitude__s'
    };

    private static final Set<String> TASK_EXCLUDED_CLONE_FIELDS = new Set<String>{
        'IsRecurrence',
        'RecurrenceActivityId',
        'RecurrenceDayOfMonth',
        'RecurrenceDayOfWeekMask',
        'RecurrenceEndDateOnly',
        'RecurrenceInstance',
        'RecurrenceInterval',
        'RecurrenceMonthOfYear',
        'RecurrenceRegeneratedType',
        'RecurrenceStartDateOnly',
        'RecurrenceTimeZoneSidKey',
        'RecurrenceType',
        'IsReminderSet',
        'ReminderDateTime',
        'TaskSubtype'
    };

    private static final List<String> STAGE_TEMPLATE = new List<String>{
        'Qualification', 'Qualification',
        'Discovery', 'Discovery',
        'Underwriting', 'Underwriting',
        'Proposal', 'Proposal',
        'Negotiation', 'Negotiation',
        'Closed Won', 'Closed Won'
    };

    private static final List<String> SECTOR_TEMPLATE = new List<String>{
        'Manufacturing', 'Technology',
        'Transportation and Warehouse', 'Construction',
        'Energy', 'Finance and Insurance',
        'Health Care', 'Wholesale',
        'Aerospace', 'Retail',
        'Educational', 'Hospitality'
    };

    private static final List<AddressSeed> MANSFIELD_ADDRESSES = new List<AddressSeed>{
        new AddressSeed('500 N Main St', 'Mansfield', 'Texas', '76063', 32.56380, -97.14120),
        new AddressSeed('1110 S Main St', 'Mansfield', 'Texas', '76063', 32.54680, -97.13590),
        new AddressSeed('1305 E Broad St', 'Mansfield', 'Texas', '76063', 32.56610, -97.11870),
        new AddressSeed('601 E Debbie Ln', 'Mansfield', 'Texas', '76063', 32.59490, -97.13150),
        new AddressSeed('1801 US 287 Frontage Rd', 'Mansfield', 'Texas', '76063', 32.58240, -97.10300),
        new AddressSeed('900 N Walnut Creek Dr', 'Mansfield', 'Texas', '76063', 32.58730, -97.12480),
        new AddressSeed('3200 E Broad St', 'Mansfield', 'Texas', '76063', 32.56810, -97.07150),
        new AddressSeed('990 N Walnut Creek Dr', 'Mansfield', 'Texas', '76063', 32.58910, -97.12370),
        new AddressSeed('2800 E Broad St', 'Mansfield', 'Texas', '76063', 32.56720, -97.08090),
        new AddressSeed('2700 E Broad St', 'Mansfield', 'Texas', '76063', 32.56700, -97.08430),
        new AddressSeed('2951 Matlock Rd', 'Mansfield', 'Texas', '76063', 32.57780, -97.11340),
        new AddressSeed('700 Heritage Pkwy', 'Mansfield', 'Texas', '76063', 32.58270, -97.14690),
        new AddressSeed('1200 N Holland Rd', 'Mansfield', 'Texas', '76063', 32.58650, -97.16120),
        new AddressSeed('1701 E Broad St', 'Mansfield', 'Texas', '76063', 32.56600, -97.11340)
    };

    public static RunResult run(Boolean dryRun) {
        return new Runner(dryRun).execute();
    }

    public static RunResult run() {
        return run(false);
    }

    private class Runner {
        private final Boolean dryRun;
        private final RunResult result;

        private final Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        private final Map<String, List<String>> cloneableFieldCache = new Map<String, List<String>>();
        private final Map<String, String> markerFieldByObject = new Map<String, String>();

        private Map<Id, Id> accountMap = new Map<Id, Id>();
        private Map<Id, Id> contactMap = new Map<Id, Id>();
        private Map<Id, Id> siteMap = new Map<Id, Id>();
        private Map<Id, Id> oppMap = new Map<Id, Id>();

        private Map<Id, List<Id>> contactIdsByAccount = new Map<Id, List<Id>>();

        Runner(Boolean isDryRun) {
            this.dryRun = isDryRun;
            this.result = new RunResult();
            this.result.dryRun = isDryRun;
            this.result.success = false;
        }

        RunResult execute() {
            try {
                preflightValidation();
                if (!result.errors.isEmpty()) {
                    return result;
                }

                cloneSourceGraph();
                generateStageCoverage();
                postRunValidation();

                result.success = result.errors.isEmpty();
                return result;
            } catch (Exception e) {
                result.errors.add('Unhandled exception: ' + e.getMessage() + ' @ line ' + e.getLineNumber());
                return result;
            }
        }

        private void preflightValidation() {
            // Developer note:
            // Lightweight gate: verify marker field and required Site geo fields before any DML.
            for (String apiName : OBJECTS_IN_SCOPE) {
                Schema.SObjectType typ = gd.get(apiName);
                if (typ == null) {
                    result.errors.add('Missing object: ' + apiName);
                    continue;
                }

                Schema.DescribeSObjectResult d = typ.getDescribe();
                Map<String, Schema.SObjectField> fieldMap = d.fields.getMap();
                if (!fieldMap.containsKey(HIDDEN_MARKER_FIELD)) {
                    result.errors.add(apiName + ' missing required marker field: ' + HIDDEN_MARKER_FIELD);
                    continue;
                }
                Schema.DescribeFieldResult markerDescribe = fieldMap.get(HIDDEN_MARKER_FIELD).getDescribe();
                if (markerDescribe.isCalculated()) {
                    result.errors.add(apiName + '.' + HIDDEN_MARKER_FIELD + ' must be non-calculated.');
                    continue;
                }
                markerFieldByObject.put(apiName, HIDDEN_MARKER_FIELD);
                result.markerStrategyByObject.put(apiName, 'hidden:' + HIDDEN_MARKER_FIELD);
            }

            Schema.DescribeSObjectResult siteDescribe = gd.get('Site__c').getDescribe();
            Map<String, Schema.SObjectField> siteFields = siteDescribe.fields.getMap();
            for (String f : REQUIRED_SITE_FIELDS) {
                if (!siteFields.containsKey(f)) {
                    result.errors.add('Site__c missing required field: ' + f);
                }
            }

            result.info.add('Preflight marker strategy: ' + JSON.serialize(result.markerStrategyByObject));
            if (dryRun) {
                result.info.add('Dry run enabled: no DML will be performed.');
            }
        }

        private void cloneSourceGraph() {
            String sourceWhere = 'Site__c != null AND ' + HIDDEN_MARKER_FIELD + ' = null';
            List<Opportunity> sourceOpps = (List<Opportunity>) Database.query(
                buildQuery('Opportunity', getCloneableFields('Opportunity'), sourceWhere)
            );
            if (sourceOpps.isEmpty()) {
                result.warnings.add('No source opportunities found where Site__c != null.');
                return;
            }

            Set<Id> sourceOppIds = new Set<Id>();
            Set<Id> sourceAccountIds = new Set<Id>();
            Set<Id> sourceSiteIds = new Set<Id>();
            Set<Id> seedContactIds = new Set<Id>();

            for (Opportunity opp : sourceOpps) {
                sourceOppIds.add(opp.Id);
                if (opp.AccountId != null) sourceAccountIds.add(opp.AccountId);
                if ((Id) opp.get('Site__c') != null) sourceSiteIds.add((Id) opp.get('Site__c'));
                if ((Id) opp.get('Primary_Contact__c') != null) seedContactIds.add((Id) opp.get('Primary_Contact__c'));
                if (opp.ContactId != null) seedContactIds.add(opp.ContactId);
            }

            List<SObject> sourceSites = sourceSiteIds.isEmpty()
                ? new List<SObject>()
                : Database.query(buildQuery('Site__c', getCloneableFields('Site__c'), 'Id IN :sourceSiteIds'));
            for (SObject site : sourceSites) {
                addIdIfPresent(seedContactIds, site.get('Owner_POC__c'));
                addIdIfPresent(seedContactIds, site.get('Property_Manager_POC__c'));
                addIdIfPresent(seedContactIds, site.get('Tenant_POC__c'));
                addIdIfPresent(sourceAccountIds, site.get('Property_Owner__c'));
                addIdIfPresent(sourceAccountIds, site.get('Property_Manager__c'));
                addIdIfPresent(sourceAccountIds, site.get('Tenant_Lessee__c'));
            }

            List<SObject> sourceFundingRequests = sourceOppIds.isEmpty()
                ? new List<SObject>()
                : Database.query(buildQuery('outfunds__Funding_Request__c', getCloneableFields('outfunds__Funding_Request__c'), 'Opportunity__c IN :sourceOppIds'));
            for (SObject fr : sourceFundingRequests) {
                addIdIfPresent(sourceAccountIds, fr.get('outfunds__Applying_Organization__c'));
                addIdIfPresent(seedContactIds, fr.get('outfunds__Applying_Contact__c'));
            }

            List<SObject> sourceAdditionalFunds = sourceOppIds.isEmpty()
                ? new List<SObject>()
                : Database.query(buildQuery('Additional_Fund__c', getCloneableFields('Additional_Fund__c'), 'Opportunity__c IN :sourceOppIds'));

            List<SObject> sourceBackgroundChecks = sourceOppIds.isEmpty()
                ? new List<SObject>()
                : Database.query(buildQuery('Background_Check__c', getCloneableFields('Background_Check__c'), 'Opportunity__c IN :sourceOppIds'));

            List<SObject> sourceTasksOpp = sourceOppIds.isEmpty()
                ? new List<SObject>()
                : Database.query(buildQuery('Task', getCloneableFields('Task'), 'WhatId IN :sourceOppIds'));
            List<SObject> sourceTasksAccount = sourceAccountIds.isEmpty()
                ? new List<SObject>()
                : Database.query(buildQuery('Task', getCloneableFields('Task'), 'WhatId IN :sourceAccountIds'));
            Map<Id, SObject> sourceTaskById = new Map<Id, SObject>();
            for (SObject task : sourceTasksOpp) sourceTaskById.put((Id) task.get('Id'), task);
            for (SObject task : sourceTasksAccount) sourceTaskById.put((Id) task.get('Id'), task);
            List<SObject> sourceTasks = sourceTaskById.values();
            for (SObject t : sourceTasks) {
                addIdIfPresent(seedContactIds, t.get('WhoId'));
            }

            List<SObject> sourceAccounts = sourceAccountIds.isEmpty()
                ? new List<SObject>()
                : Database.query(buildQuery('Account', getCloneableFields('Account'), 'Id IN :sourceAccountIds'));

            Set<Id> sourceContactIds = new Set<Id>();
            sourceContactIds.addAll(seedContactIds);
            if (!sourceAccountIds.isEmpty()) {
                List<SObject> contactsByAccount = Database.query(buildQuery('Contact', getCloneableFields('Contact'), 'AccountId IN :sourceAccountIds'));
                for (SObject c : contactsByAccount) {
                    sourceContactIds.add((Id) c.get('Id'));
                }
            }

            List<SObject> sourceContacts = sourceContactIds.isEmpty()
                ? new List<SObject>()
                : Database.query(buildQuery('Contact', getCloneableFields('Contact'), 'Id IN :sourceContactIds'));

            accountMap = cloneBySource('Account', sourceAccounts, null);
            contactMap = cloneContacts(sourceContacts, accountMap);
            siteMap = cloneSites(sourceSites, accountMap, contactMap);
            oppMap = cloneOpportunities(sourceOpps, accountMap, contactMap, siteMap);

            cloneFundingRequests(sourceFundingRequests, accountMap, contactMap, oppMap);
            cloneAdditionalFunds(sourceAdditionalFunds, oppMap);
            cloneBackgroundChecks(sourceBackgroundChecks, oppMap);
            cloneTasks(sourceTasks, oppMap, accountMap, contactMap);

            buildContactIndexByAccount();
        }

        private Map<Id, Id> cloneContacts(List<SObject> sourceContacts, Map<Id, Id> localAccountMap) {
            Map<Id, Id> mapOut = cloneBySource('Contact', sourceContacts, null);
            if (mapOut.isEmpty()) return mapOut;

            List<SObject> updates = new List<SObject>();
            for (SObject src : sourceContacts) {
                Id cloneId = mapOut.get((Id) src.get('Id'));
                if (cloneId == null) continue;
                Id srcAccountId = (Id) src.get('AccountId');
                Id clonedAccountId = srcAccountId == null ? null : localAccountMap.get(srcAccountId);
                if (clonedAccountId != null) {
                    SObject upd = gd.get('Contact').newSObject(cloneId);
                    upd.put('AccountId', clonedAccountId);
                    updates.add(upd);
                }
            }
            if (!dryRun && !updates.isEmpty()) {
                updateChunked('Contact', updates);
            }
            return mapOut;
        }

        private Map<Id, Id> cloneSites(List<SObject> sourceSites, Map<Id, Id> localAccountMap, Map<Id, Id> localContactMap) {
            Map<Id, Id> mapOut = new Map<Id, Id>();
            if (sourceSites == null || sourceSites.isEmpty()) return mapOut;

            String objectApiName = 'Site__c';
            String markerField = markerFieldByObject.get(objectApiName);

            Map<Id, String> keyBySourceId = new Map<Id, String>();
            Map<String, Id> sourceIdByKey = new Map<String, Id>();
            for (SObject src : sourceSites) {
                Id sourceId = (Id) src.get('Id');
                String key = RUN_NAMESPACE + '_' + shortObjectToken(objectApiName) + '_' + (String) sourceId;
                keyBySourceId.put(sourceId, key);
                sourceIdByKey.put(key, sourceId);
            }

            Set<String> keys = new Set<String>(sourceIdByKey.keySet());
            String q = 'SELECT Id, ' + markerField + ' FROM Site__c WHERE ' + markerField + ' IN :keys';
            for (SObject existing : Database.query(q)) {
                String key = (String) existing.get(markerField);
                Id sourceId = sourceIdByKey.get(key);
                if (sourceId != null) {
                    mapOut.put(sourceId, (Id) existing.get('Id'));
                    incrementMap(result.reusedByObject, objectApiName, 1);
                }
            }

            List<SObject> inserts = new List<SObject>();
            List<Id> sourceOrder = new List<Id>();
            Integer i = 0;
            for (SObject src : sourceSites) {
                Id sourceId = (Id) src.get('Id');
                if (mapOut.containsKey(sourceId)) {
                    i++;
                    continue;
                }

                AddressSeed seed = MANSFIELD_ADDRESSES[Math.mod(i, MANSFIELD_ADDRESSES.size())];
                i++;

                SObject rec = copyCreateableFields(objectApiName, src, null);
                remapLookupCreateable(rec, 'Property_Owner__c', src, localAccountMap);
                remapLookupCreateable(rec, 'Property_Manager__c', src, localAccountMap);
                remapLookupCreateable(rec, 'Tenant_Lessee__c', src, localAccountMap);
                remapLookupCreateable(rec, 'Owner_POC__c', src, localContactMap);
                remapLookupCreateable(rec, 'Property_Manager_POC__c', src, localContactMap);
                remapLookupCreateable(rec, 'Tenant_POC__c', src, localContactMap);

                if (isFieldCreateable('Site__c', 'Street_Address__c')) rec.put('Street_Address__c', seed.street);
                if (isFieldCreateable('Site__c', 'City__c')) rec.put('City__c', seed.city);
                if (isFieldCreateable('Site__c', 'State__c')) rec.put('State__c', seed.state);
                if (isFieldCreateable('Site__c', 'Postal_Zip_Code__c')) rec.put('Postal_Zip_Code__c', seed.postalCode);
                if (isFieldCreateable('Site__c', 'Latitude__c')) rec.put('Latitude__c', seed.latitude);
                if (isFieldCreateable('Site__c', 'Longitude__c')) rec.put('Longitude__c', seed.longitude);
                if (isFieldCreateable('Site__c', 'Verified_Latitude__c')) rec.put('Verified_Latitude__c', seed.latitude);
                if (isFieldCreateable('Site__c', 'Verified_Longitude__c')) rec.put('Verified_Longitude__c', seed.longitude);
                if (isFieldCreateable('Site__c', 'Site_Geolocation__Latitude__s')) rec.put('Site_Geolocation__Latitude__s', seed.latitude);
                if (isFieldCreateable('Site__c', 'Site_Geolocation__Longitude__s')) rec.put('Site_Geolocation__Longitude__s', seed.longitude);

                applyMarker(objectApiName, rec, keyBySourceId.get(sourceId), src);
                inserts.add(rec);
                sourceOrder.add(sourceId);
            }

            if (dryRun) {
                incrementMap(result.insertedByObject, objectApiName, inserts.size());
                return mapOut;
            }

            applyOwnerFallback(objectApiName, inserts);
            for (Integer j = 0; j < inserts.size(); j += DML_CHUNK_SIZE) {
                Integer endIdx = Math.min(j + DML_CHUNK_SIZE, inserts.size());
                List<SObject> chunk = listChunk(inserts, j, endIdx);
                Database.SaveResult[] sr = Database.insert(chunk, false);
                for (Integer k = 0; k < sr.size(); k++) {
                    Id sourceId = sourceOrder[j + k];
                    if (sr[k].isSuccess()) {
                        mapOut.put(sourceId, sr[k].getId());
                        incrementMap(result.insertedByObject, objectApiName, 1);
                    } else {
                        result.errors.add('Site__c clone failed for source ' + sourceId + ': ' + firstError(sr[k]));
                    }
                }
            }
            return mapOut;
        }

        private Map<Id, Id> cloneOpportunities(List<Opportunity> sourceOpps, Map<Id, Id> localAccountMap, Map<Id, Id> localContactMap, Map<Id, Id> localSiteMap) {
            List<SObject> src = new List<SObject>();
            src.addAll(sourceOpps);
            Map<Id, Id> mapOut = cloneBySource('Opportunity', src, null);
            if (mapOut.isEmpty()) return mapOut;

            List<SObject> updates = new List<SObject>();
            for (Opportunity source : sourceOpps) {
                Id cloneId = mapOut.get(source.Id);
                if (cloneId == null) continue;
                SObject upd = gd.get('Opportunity').newSObject(cloneId);

                Id srcAcc = source.AccountId;
                Id srcSite = (Id) source.get('Site__c');
                Id srcPrimary = (Id) source.get('Primary_Contact__c');

                if (srcAcc != null && localAccountMap.containsKey(srcAcc)) upd.put('AccountId', localAccountMap.get(srcAcc));
                if (srcSite != null && localSiteMap.containsKey(srcSite)) upd.put('Site__c', localSiteMap.get(srcSite));
                if (srcPrimary != null && localContactMap.containsKey(srcPrimary) && isFieldUpdateable('Opportunity', 'Primary_Contact__c')) {
                    upd.put('Primary_Contact__c', localContactMap.get(srcPrimary));
                }
                if (source.ContactId != null && localContactMap.containsKey(source.ContactId) && isFieldUpdateable('Opportunity', 'ContactId')) {
                    upd.put('ContactId', localContactMap.get(source.ContactId));
                }
                updates.add(upd);
            }

            if (!dryRun && !updates.isEmpty()) {
                updateChunked('Opportunity', updates);
            }
            return mapOut;
        }

        private void cloneFundingRequests(List<SObject> sourceRecords, Map<Id, Id> localAccountMap, Map<Id, Id> localContactMap, Map<Id, Id> localOppMap) {
            Map<Id, Id> frMap = cloneBySource('outfunds__Funding_Request__c', sourceRecords, null);
            if (frMap.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            for (SObject src : sourceRecords) {
                Id cloneId = frMap.get((Id) src.get('Id'));
                if (cloneId == null) continue;
                SObject upd = gd.get('outfunds__Funding_Request__c').newSObject(cloneId);

                remapLookup(upd, 'Opportunity__c', src, localOppMap);
                remapLookup(upd, 'outfunds__Applying_Organization__c', src, localAccountMap);
                remapLookup(upd, 'outfunds__Applying_Contact__c', src, localContactMap);

                // Funding Program is preserved exactly and never cloned.
                upd.put('outfunds__FundingProgram__c', src.get('outfunds__FundingProgram__c'));
                updates.add(upd);
            }

            if (!dryRun && !updates.isEmpty()) {
                updateChunked('outfunds__Funding_Request__c', updates);
            }
        }

        private void cloneAdditionalFunds(List<SObject> sourceRecords, Map<Id, Id> localOppMap) {
            Map<Id, Id> recMap = cloneBySource('Additional_Fund__c', sourceRecords, null);
            if (recMap.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            for (SObject src : sourceRecords) {
                Id cloneId = recMap.get((Id) src.get('Id'));
                if (cloneId == null) continue;
                SObject upd = gd.get('Additional_Fund__c').newSObject(cloneId);
                remapLookup(upd, 'Opportunity__c', src, localOppMap);
                updates.add(upd);
            }

            if (!dryRun && !updates.isEmpty()) {
                updateChunked('Additional_Fund__c', updates);
            }
        }

        private void cloneBackgroundChecks(List<SObject> sourceRecords, Map<Id, Id> localOppMap) {
            if (sourceRecords == null || sourceRecords.isEmpty()) return;

            String objectApiName = 'Background_Check__c';
            String hiddenMarkerField = markerFieldByObject.get(objectApiName);

            Map<Id, String> keyBySourceId = new Map<Id, String>();
            Map<String, Id> sourceIdByKey = new Map<String, Id>();
            for (SObject src : sourceRecords) {
                Id srcId = (Id) src.get('Id');
                String key = RUN_NAMESPACE + '_' + shortObjectToken(objectApiName) + '_' + (String) srcId;
                keyBySourceId.put(srcId, key);
                sourceIdByKey.put(key, srcId);
            }

            Set<Id> existingSourceIds = new Set<Id>();
            Set<String> keys = new Set<String>(sourceIdByKey.keySet());
            String q = 'SELECT Id, ' + hiddenMarkerField + ' FROM ' + objectApiName + ' WHERE ' + hiddenMarkerField + ' IN :keys';
            for (SObject existing : Database.query(q)) {
                String key = (String) existing.get(hiddenMarkerField);
                if (sourceIdByKey.containsKey(key)) {
                    existingSourceIds.add(sourceIdByKey.get(key));
                    incrementMap(result.reusedByObject, objectApiName, 1);
                }
            }

            List<SObject> inserts = new List<SObject>();
            for (SObject src : sourceRecords) {
                Id srcId = (Id) src.get('Id');
                if (existingSourceIds.contains(srcId)) continue;

                Id srcOpp = (Id) src.get('Opportunity__c');
                if (srcOpp == null || !localOppMap.containsKey(srcOpp)) {
                    continue;
                }

                SObject rec = copyCreateableFields(objectApiName, src, null);
                if (isFieldCreateable(objectApiName, 'Opportunity__c')) {
                    rec.put('Opportunity__c', localOppMap.get(srcOpp));
                }
                applyMarker(objectApiName, rec, keyBySourceId.get(srcId), src);
                inserts.add(rec);
            }

            if (dryRun) {
                incrementMap(result.insertedByObject, objectApiName, inserts.size());
                return;
            }

            applyOwnerFallback(objectApiName, inserts);
            for (Integer i = 0; i < inserts.size(); i += DML_CHUNK_SIZE) {
                Integer endIdx = Math.min(i + DML_CHUNK_SIZE, inserts.size());
                List<SObject> chunk = listChunk(inserts, i, endIdx);
                Database.SaveResult[] sr = Database.insert(chunk, false);
                for (Database.SaveResult one : sr) {
                    if (one.isSuccess()) {
                        incrementMap(result.insertedByObject, objectApiName, 1);
                    } else {
                        result.errors.add('Background_Check__c clone failed: ' + firstError(one));
                    }
                }
            }
        }

        private void cloneTasks(List<SObject> sourceTasks, Map<Id, Id> localOppMap, Map<Id, Id> localAccountMap, Map<Id, Id> localContactMap) {
            List<SObject> eligibleTasks = new List<SObject>();
            for (SObject src : sourceTasks) {
                Id srcWhat = (Id) src.get('WhatId');
                if (srcWhat != null && (localOppMap.containsKey(srcWhat) || localAccountMap.containsKey(srcWhat))) {
                    eligibleTasks.add(src);
                }
            }

            Map<Id, Id> taskMap = cloneBySource('Task', eligibleTasks, TASK_EXCLUDED_CLONE_FIELDS);
            if (taskMap.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            for (SObject src : eligibleTasks) {
                Id cloneId = taskMap.get((Id) src.get('Id'));
                if (cloneId == null) continue;
                SObject upd = gd.get('Task').newSObject(cloneId);

                Id srcWhat = (Id) src.get('WhatId');
                Id mappedWhat;
                if (srcWhat != null && localOppMap.containsKey(srcWhat)) {
                    mappedWhat = localOppMap.get(srcWhat);
                } else if (srcWhat != null && localAccountMap.containsKey(srcWhat)) {
                    mappedWhat = localAccountMap.get(srcWhat);
                }
                if (mappedWhat == null) continue;

                upd.put('WhatId', mappedWhat);
                Id srcWho = (Id) src.get('WhoId');
                if (srcWho != null && localContactMap.containsKey(srcWho)) {
                    upd.put('WhoId', localContactMap.get(srcWho));
                } else {
                    upd.put('WhoId', null);
                }
                updates.add(upd);
            }

            if (!dryRun && !updates.isEmpty()) {
                updateChunked('Task', updates);
            }
        }

        private void generateStageCoverage() {
            if (accountMap.isEmpty()) {
                result.warnings.add('No cloned accounts available for generated opportunities. Skipping stage coverage generation.');
                return;
            }

            List<Id> accountIds = new List<Id>(new Set<Id>(accountMap.values()));
            List<Id> siteIds = new List<Id>(new Set<Id>(siteMap.values()));
            List<Id> pairAccounts = new List<Id>();
            List<Id> pairSites = new List<Id>();

            if (!oppMap.isEmpty()) {
                Set<Id> clonedOppIds = new Set<Id>(oppMap.values());
                List<Opportunity> clonedOpps = [
                    SELECT Id, AccountId, Site__c
                    FROM Opportunity
                    WHERE Id IN :clonedOppIds
                ];
                for (Opportunity o : clonedOpps) {
                    if (o.AccountId != null) {
                        pairAccounts.add(o.AccountId);
                        pairSites.add((Id) o.get('Site__c'));
                    }
                }
            }
            if (pairAccounts.isEmpty()) {
                for (Id aid : accountIds) {
                    pairAccounts.add(aid);
                    pairSites.add(siteIds.isEmpty() ? null : siteIds[Math.mod(pairAccounts.size() - 1, siteIds.size())]);
                }
            }

            List<String> genKeys = new List<String>();
            for (Integer i = 0; i < STAGE_TEMPLATE.size(); i++) {
                String stageKey = sanitizeKeyToken(STAGE_TEMPLATE[i]);
                genKeys.add(RUN_NAMESPACE + '_OPP_GEN_' + stageKey + '_' + leftPad(String.valueOf(i + 1), 2));
            }

            Set<String> existingGenKeys = new Set<String>();
            if (markerFieldByObject.containsKey('Opportunity')) {
                String markerField = markerFieldByObject.get('Opportunity');
                String q = 'SELECT Id, ' + markerField + ' FROM Opportunity WHERE ' + markerField + ' IN :genKeys';
                for (SObject rec : Database.query(q)) {
                    existingGenKeys.add((String) rec.get(markerField));
                }
            }

            List<SObject> toInsert = new List<SObject>();
            List<String> missingGenKeys = new List<String>();
            for (Integer i = 0; i < STAGE_TEMPLATE.size(); i++) {
                String key = genKeys[i];
                if (existingGenKeys.contains(key)) continue;

                String stage = STAGE_TEMPLATE[i];
                String sector = SECTOR_TEMPLATE[i];
                Id accountId = pairAccounts[Math.mod(i, pairAccounts.size())];
                Id siteId = pairSites[Math.mod(i, pairSites.size())];
                Boolean attachSite = !siteIds.isEmpty() && i < 10;

                SObject opp = gd.get('Opportunity').newSObject();
                opp.put('Name', 'Mansfield ' + sector + ' Expansion ' + leftPad(String.valueOf(i + 1), 2));
                opp.put('AccountId', accountId);
                opp.put('StageName', stage);
                opp.put('CloseDate', Date.today().addDays(30 + (i * 10)));
                opp.put('Sector__c', sector);

                Decimal jobsCreated = 20 + (i * 8);
                Decimal jobsRetained = 10 + (i * 5);
                Decimal indirectJobs = 8 + (i * 4);
                Decimal avgWage = 48000 + (i * 2200);
                Decimal capInvestment = 1500000 + (i * 650000);
                Decimal amount = 250000 + (i * 90000);

                if (isFieldCreateable('Opportunity', 'Jobs_Created_Estimated__c')) opp.put('Jobs_Created_Estimated__c', jobsCreated);
                if (isFieldCreateable('Opportunity', 'Jobs_Retained_Estimated__c')) opp.put('Jobs_Retained_Estimated__c', jobsRetained);
                if (isFieldCreateable('Opportunity', 'Indirect_Jobs__c')) opp.put('Indirect_Jobs__c', indirectJobs);
                if (isFieldCreateable('Opportunity', 'Indirect_Average_Wages__c')) opp.put('Indirect_Average_Wages__c', avgWage);
                if (isFieldCreateable('Opportunity', 'Capital_Investment__c')) opp.put('Capital_Investment__c', capInvestment);
                opp.put('Amount', amount);

                if (attachSite && siteId != null && isFieldCreateable('Opportunity', 'Site__c')) {
                    opp.put('Site__c', siteId);
                }

                Id preferredContact = getPreferredContactForAccount(accountId);
                if (preferredContact != null && isFieldCreateable('Opportunity', 'Primary_Contact__c')) {
                    opp.put('Primary_Contact__c', preferredContact);
                }

                applyMarker('Opportunity', opp, key, null);
                toInsert.add(opp);
                missingGenKeys.add(key);
            }

            List<Id> insertedGeneratedOppIds = new List<Id>();
            if (dryRun) {
                incrementMap(result.insertedByObject, 'Opportunity', toInsert.size());
            } else if (!toInsert.isEmpty()) {
                applyOwnerFallback('Opportunity', toInsert);
                for (Integer i = 0; i < toInsert.size(); i += DML_CHUNK_SIZE) {
                    Integer endIdx = Math.min(i + DML_CHUNK_SIZE, toInsert.size());
                    List<SObject> chunk = listChunk(toInsert, i, endIdx);
                    Database.SaveResult[] sr = Database.insert(chunk, false);
                    for (Database.SaveResult one : sr) {
                        if (one.isSuccess()) {
                            insertedGeneratedOppIds.add(one.getId());
                            incrementMap(result.insertedByObject, 'Opportunity', 1);
                        } else {
                            result.errors.add('Generated Opportunity insert failed: ' + firstError(one));
                        }
                    }
                }
            }

            if (dryRun || insertedGeneratedOppIds.isEmpty()) {
                return;
            }

            List<Opportunity> generatedOpps = [
                SELECT Id, StageName, Name
                FROM Opportunity
                WHERE Id IN :insertedGeneratedOppIds
            ];

            List<SObject> bgToInsert = new List<SObject>();
            Set<String> bgKeys = new Set<String>();
            Boolean createdProposalSample = false;
            for (Opportunity opp : generatedOpps) {
                Boolean createBg = opp.StageName == 'Underwriting';
                if (!createBg && opp.StageName == 'Proposal') {
                    createBg = !createdProposalSample;
                    if (createBg) {
                        createdProposalSample = true;
                    }
                }
                if (!createBg) continue;

                String bgKey = RUN_NAMESPACE + '_BG_GEN_' + (String) opp.Id;
                bgKeys.add(bgKey);

                SObject bg = gd.get('Background_Check__c').newSObject();
                bg.put('Opportunity__c', opp.Id);
                if (isFieldCreateable('Background_Check__c', 'Type__c')) bg.put('Type__c', 'Circuit Court');
                if (isFieldCreateable('Background_Check__c', 'Result__c')) bg.put('Result__c', 'Clear');
                if (isFieldCreateable('Background_Check__c', 'Accepted__c')) bg.put('Accepted__c', true);
                if (isFieldCreateable('Background_Check__c', 'Reason__c')) bg.put('Reason__c', 'Generated demo background check');
                applyMarker('Background_Check__c', bg, bgKey, null);
                bgToInsert.add(bg);
            }

            if (bgToInsert.isEmpty()) return;

            Set<String> existingKeys = new Set<String>();
            String bgMarkerField = markerFieldByObject.get('Background_Check__c');
            String existingBgQuery = 'SELECT Id, ' + bgMarkerField + ' FROM Background_Check__c WHERE ' +
                bgMarkerField + ' IN :bgKeys';
            for (SObject rec : Database.query(existingBgQuery)) {
                existingKeys.add((String) rec.get(bgMarkerField));
            }

            List<SObject> filtered = new List<SObject>();
            for (SObject bg : bgToInsert) {
                String bgKey = (String) bg.get(bgMarkerField);
                if (!existingKeys.contains(bgKey)) {
                    filtered.add(bg);
                }
            }

            if (!filtered.isEmpty()) {
                applyOwnerFallback('Background_Check__c', filtered);
                for (Integer i = 0; i < filtered.size(); i += DML_CHUNK_SIZE) {
                    Integer endIdx = Math.min(i + DML_CHUNK_SIZE, filtered.size());
                    List<SObject> chunk = listChunk(filtered, i, endIdx);
                    Database.SaveResult[] sr = Database.insert(chunk, false);
                    for (Database.SaveResult one : sr) {
                        if (one.isSuccess()) {
                            incrementMap(result.insertedByObject, 'Background_Check__c', 1);
                        } else {
                            result.errors.add('Generated Background_Check__c insert failed: ' + firstError(one));
                        }
                    }
                }
            }
        }

        private void postRunValidation() {
            String sourceCountSoql = 'SELECT Count() FROM Opportunity WHERE Site__c != null AND ' +
                HIDDEN_MARKER_FIELD + ' = null';
            Integer sourceOppCount = Database.countQuery(sourceCountSoql);
            result.info.add('Post-run check: source opportunities with Site__c != null = ' + sourceOppCount);

            if (!dryRun) {
                String oppMarkerField = markerFieldByObject.get('Opportunity');
                if (oppMarkerField != null) {
                    String likeValue = RUN_NAMESPACE + '_OPP_GEN_%';
                    String countSoql = 'SELECT COUNT() FROM Opportunity WHERE ' + oppMarkerField +
                        ' LIKE \'' + String.escapeSingleQuotes(likeValue) + '\'';
                    Integer generatedOppCount = Database.countQuery(countSoql);
                    result.info.add('Generated opportunities currently in org: ' + generatedOppCount);
                }
            }
        }

        private Map<Id, Id> cloneBySource(String objectApiName, List<SObject> sourceRecords, Set<String> excludedFields) {
            Map<Id, Id> out = new Map<Id, Id>();
            if (sourceRecords == null || sourceRecords.isEmpty()) {
                return out;
            }

            String hiddenMarkerField = markerFieldByObject.get(objectApiName);

            Map<Id, String> keyBySourceId = new Map<Id, String>();
            Map<String, Id> sourceIdByKey = new Map<String, Id>();

            for (SObject src : sourceRecords) {
                Id sourceId = (Id) src.get('Id');
                String key = RUN_NAMESPACE + '_' + shortObjectToken(objectApiName) + '_' + (String) sourceId;
                keyBySourceId.put(sourceId, key);
                sourceIdByKey.put(key, sourceId);
            }

            Set<String> keys = new Set<String>(sourceIdByKey.keySet());
            String q = 'SELECT Id, ' + hiddenMarkerField + ' FROM ' + objectApiName + ' WHERE ' + hiddenMarkerField + ' IN :keys';
            for (SObject existing : Database.query(q)) {
                String key = (String) existing.get(hiddenMarkerField);
                Id sourceId = sourceIdByKey.get(key);
                if (sourceId != null) {
                    out.put(sourceId, (Id) existing.get('Id'));
                    incrementMap(result.reusedByObject, objectApiName, 1);
                }
            }

            List<SObject> toInsert = new List<SObject>();
            List<Id> sourceOrder = new List<Id>();
            for (SObject src : sourceRecords) {
                Id sourceId = (Id) src.get('Id');
                if (out.containsKey(sourceId)) continue;

                SObject clone = copyCreateableFields(objectApiName, src, excludedFields);
                applyMarker(objectApiName, clone, keyBySourceId.get(sourceId), src);
                toInsert.add(clone);
                sourceOrder.add(sourceId);
            }

            if (dryRun) {
                incrementMap(result.insertedByObject, objectApiName, toInsert.size());
                return out;
            }

            applyOwnerFallback(objectApiName, toInsert);
            for (Integer i = 0; i < toInsert.size(); i += DML_CHUNK_SIZE) {
                Integer endIdx = Math.min(i + DML_CHUNK_SIZE, toInsert.size());
                List<SObject> chunk = listChunk(toInsert, i, endIdx);
                Database.SaveResult[] sr = Database.insert(chunk, false);
                for (Integer j = 0; j < sr.size(); j++) {
                    Id sourceId = sourceOrder[i + j];
                    if (sr[j].isSuccess()) {
                        out.put(sourceId, sr[j].getId());
                        incrementMap(result.insertedByObject, objectApiName, 1);
                    } else {
                        result.errors.add(objectApiName + ' clone failed for source ' + sourceId + ': ' + firstError(sr[j]));
                    }
                }
            }
            return out;
        }

        private void applyMarker(String objectApiName, SObject target, String deterministicKey, SObject source) {
            target.put(markerFieldByObject.get(objectApiName), deterministicKey);
        }

        private SObject copyCreateableFields(String objectApiName, SObject source, Set<String> excludedFields) {
            SObject target = gd.get(objectApiName).newSObject();
            Set<String> exclusions = excludedFields == null ? new Set<String>() : new Set<String>(excludedFields);
            Set<String> exclusionLower = new Set<String>();
            for (String ex : exclusions) {
                if (!String.isBlank(ex)) exclusionLower.add(ex.toLowerCase());
            }

            for (String fieldName : getCloneableFields(objectApiName)) {
                if (objectApiName == 'Account' && (fieldName.endsWith('__pc') || fieldName.startsWith('Person'))) continue;
                if (objectApiName == 'Site__c' && fieldName.startsWith('Site_Geolocation__')) continue;
                if (exclusionLower.contains(fieldName.toLowerCase())) continue;
                Object value = source.get(fieldName);
                if (value != null) {
                    try {
                        target.put(fieldName, value);
                    } catch (Exception ignored) {
                        // Some activity/system fields report createable but are not practically settable.
                    }
                }
            }
            return target;
        }

        private List<String> getCloneableFields(String objectApiName) {
            if (cloneableFieldCache.containsKey(objectApiName)) {
                return cloneableFieldCache.get(objectApiName);
            }

            Map<String, Schema.SObjectField> fieldMap = gd.get(objectApiName).getDescribe().fields.getMap();
            List<String> out = new List<String>();
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
                if (!dfr.isCreateable()) continue;
                if (dfr.isCalculated()) continue;
                if (dfr.isAutoNumber()) continue;
                if (dfr.isUnique()) continue;
                if (dfr.isExternalId()) continue;
                if (fieldName == 'Id') continue;
                out.add(fieldName);
            }

            out.sort();
            cloneableFieldCache.put(objectApiName, out);
            return out;
        }

        private String buildQuery(String objectApiName, List<String> fields, String whereClause) {
            Set<String> fieldSet = new Set<String>();
            fieldSet.addAll(fields);
            fieldSet.add('Id');

            if (markerFieldByObject.containsKey(objectApiName)) {
                fieldSet.add(markerFieldByObject.get(objectApiName));
            }

            Map<String, String> canonicalByLower = new Map<String, String>();
            for (String f : fieldSet) {
                if (String.isBlank(f)) continue;
                canonicalByLower.put(f.toLowerCase(), f);
            }
            List<String> fieldList = new List<String>();
            fieldList.addAll(canonicalByLower.values());
            fieldList.sort();
            return 'SELECT ' + String.join(fieldList, ', ') + ' FROM ' + objectApiName + ' WHERE ' + whereClause;
        }

        private Boolean isFieldCreateable(String objectApiName, String fieldApiName) {
            Map<String, Schema.SObjectField> fields = gd.get(objectApiName).getDescribe().fields.getMap();
            if (!fields.containsKey(fieldApiName)) return false;
            Schema.DescribeFieldResult dfr = fields.get(fieldApiName).getDescribe();
            return dfr.isCreateable();
        }

        private Boolean isFieldUpdateable(String objectApiName, String fieldApiName) {
            Map<String, Schema.SObjectField> fields = gd.get(objectApiName).getDescribe().fields.getMap();
            if (!fields.containsKey(fieldApiName)) return false;
            Schema.DescribeFieldResult dfr = fields.get(fieldApiName).getDescribe();
            return dfr.isUpdateable();
        }

        private void remapLookup(SObject target, String fieldApiName, SObject source, Map<Id, Id> lookupMap) {
            if (!isFieldUpdateable(target.getSObjectType().getDescribe().getName(), fieldApiName)) {
                return;
            }
            Id srcId = (Id) source.get(fieldApiName);
            if (srcId != null && lookupMap.containsKey(srcId)) {
                target.put(fieldApiName, lookupMap.get(srcId));
            }
        }

        private void remapLookupCreateable(SObject target, String fieldApiName, SObject source, Map<Id, Id> lookupMap) {
            if (!isFieldCreateable(target.getSObjectType().getDescribe().getName(), fieldApiName)) {
                return;
            }
            Id srcId = (Id) source.get(fieldApiName);
            if (srcId != null && lookupMap.containsKey(srcId)) {
                target.put(fieldApiName, lookupMap.get(srcId));
            }
        }

        private void addIdIfPresent(Set<Id> bucket, Object rawValue) {
            if (rawValue == null) return;
            try {
                bucket.add((Id) rawValue);
            } catch (Exception ex) {
                // Ignore non-Id values.
            }
        }

        private void buildContactIndexByAccount() {
            if (contactMap.isEmpty()) return;
            List<Contact> clonedContacts = [SELECT Id, AccountId FROM Contact WHERE Id IN :new Set<Id>(contactMap.values())];
            for (Contact c : clonedContacts) {
                if (c.AccountId == null) continue;
                if (!contactIdsByAccount.containsKey(c.AccountId)) {
                    contactIdsByAccount.put(c.AccountId, new List<Id>());
                }
                contactIdsByAccount.get(c.AccountId).add(c.Id);
            }
        }

        private Id getPreferredContactForAccount(Id accountId) {
            if (accountId == null || !contactIdsByAccount.containsKey(accountId) || contactIdsByAccount.get(accountId).isEmpty()) {
                return null;
            }
            return contactIdsByAccount.get(accountId)[0];
        }

        private String sanitizeKeyToken(String raw) {
            String v = raw == null ? '' : raw.toUpperCase();
            v = v.replace(' ', '_');
            v = v.replace('-', '_');
            return v;
        }

        private String leftPad(String value, Integer len) {
            String v = value == null ? '' : value;
            while (v.length() < len) {
                v = '0' + v;
            }
            return v;
        }

        private String shortObjectToken(String objectApiName) {
            if (objectApiName == 'Account') return 'ACCOUNT';
            if (objectApiName == 'Contact') return 'CONTACT';
            if (objectApiName == 'Opportunity') return 'OPP';
            if (objectApiName == 'Site__c') return 'SITE';
            if (objectApiName == 'outfunds__Funding_Request__c') return 'FR';
            if (objectApiName == 'Additional_Fund__c') return 'AF';
            if (objectApiName == 'Background_Check__c') return 'BG';
            if (objectApiName == 'Task') return 'TASK';
            return objectApiName.replace('__c', '').toUpperCase();
        }

        private void incrementMap(Map<String, Integer> target, String key, Integer delta) {
            Integer current = target.containsKey(key) ? target.get(key) : 0;
            target.put(key, current + delta);
        }

        private String firstError(Database.SaveResult sr) {
            if (sr == null || sr.getErrors() == null || sr.getErrors().isEmpty()) {
                return 'Unknown DML error';
            }
            Database.Error e = sr.getErrors()[0];
            return e.getStatusCode() + ' - ' + e.getMessage();
        }

        private void updateChunked(String objectApiName, List<SObject> updates) {
            for (Integer i = 0; i < updates.size(); i += DML_CHUNK_SIZE) {
                Integer endIdx = Math.min(i + DML_CHUNK_SIZE, updates.size());
                List<SObject> chunk = listChunk(updates, i, endIdx);
                Database.SaveResult[] sr = Database.update(chunk, false);
                for (Integer j = 0; j < sr.size(); j++) {
                    if (!sr[j].isSuccess()) {
                        result.errors.add(objectApiName + ' update failed for ' + (Id) chunk[j].get('Id') + ': ' + firstError(sr[j]));
                    }
                }
            }
        }

        private void applyOwnerFallback(String objectApiName, List<SObject> records) {
            if (records == null || records.isEmpty() || !isFieldCreateable(objectApiName, 'OwnerId')) {
                return;
            }

            Set<Id> ownerIds = new Set<Id>();
            for (SObject rec : records) {
                Id ownerId = (Id) rec.get('OwnerId');
                if (ownerId != null) ownerIds.add(ownerId);
            }
            if (ownerIds.isEmpty()) return;

            Set<Id> validOwnerIds = resolveValidOwnerIds(objectApiName, ownerIds);
            Id fallbackOwnerId = UserInfo.getUserId();
            for (SObject rec : records) {
                Id ownerId = (Id) rec.get('OwnerId');
                if (ownerId != null && !validOwnerIds.contains(ownerId)) {
                    rec.put('OwnerId', fallbackOwnerId);
                }
            }
        }

        private Set<Id> resolveValidOwnerIds(String objectApiName, Set<Id> ownerIds) {
            Set<Id> validOwnerIds = new Set<Id>();
            Map<String, Schema.SObjectField> fields = gd.get(objectApiName).getDescribe().fields.getMap();
            if (!fields.containsKey('OwnerId')) return validOwnerIds;

            Schema.DescribeFieldResult ownerDescribe = fields.get('OwnerId').getDescribe();
            for (Schema.SObjectType refType : ownerDescribe.getReferenceTo()) {
                String refObject = refType.getDescribe().getName();
                try {
                    String query = 'SELECT Id FROM ' + refObject + ' WHERE Id IN :ownerIds';
                    if (refObject == 'User') {
                        query += ' AND IsActive = true';
                    }
                    for (SObject rec : Database.query(query)) {
                        validOwnerIds.add((Id) rec.get('Id'));
                    }
                } catch (Exception ignored) {
                    // Ignore owner-reference types that cannot be queried in this context.
                }
            }
            return validOwnerIds;
        }

        private List<SObject> listChunk(List<SObject> source, Integer startIdx, Integer endIdxExclusive) {
            List<SObject> chunk = new List<SObject>();
            for (Integer i = startIdx; i < endIdxExclusive; i++) {
                chunk.add(source[i]);
            }
            return chunk;
        }
    }

    private class AddressSeed {
        public String street;
        public String city;
        public String state;
        public String postalCode;
        public Decimal latitude;
        public Decimal longitude;

        AddressSeed(String s, String c, String st, String p, Decimal lat, Decimal lon) {
            street = s;
            city = c;
            state = st;
            postalCode = p;
            latitude = lat;
            longitude = lon;
        }
    }
}
