List<String> logs = new List<String>();

void deleteBySoql(String objectApiName, String soql, List<String> logsRef) {
    List<SObject> rows = Database.query(soql);
    Integer attempted = rows.size();
    Integer deleted = 0;
    Integer failed = 0;
    List<String> sampleErrors = new List<String>();

    if (!rows.isEmpty()) {
        Database.DeleteResult[] dr = Database.delete(rows, false);
        for (Database.DeleteResult one : dr) {
            if (one.isSuccess()) {
                deleted++;
            } else {
                failed++;
                if (sampleErrors.size() < 5) {
                    sampleErrors.add(one.getErrors()[0].getStatusCode() + ': ' + one.getErrors()[0].getMessage());
                }
            }
        }
    }

    logsRef.add(objectApiName + ' attempted=' + attempted + ' deleted=' + deleted + ' failed=' + failed + ' sampleErrors=' + JSON.serialize(sampleErrors));
}

// Child-first cleanup
deleteBySoql('Task', 'SELECT Id FROM Task WHERE analyticsdemo_batch_id__c LIKE \'ECONDEV_DEMO_TASK_%\'', logs);
deleteBySoql('Background_Check__c', 'SELECT Id FROM Background_Check__c WHERE analyticsdemo_batch_id__c LIKE \'ECONDEV_DEMO_BG_%\'', logs);
deleteBySoql('Additional_Fund__c', 'SELECT Id FROM Additional_Fund__c WHERE analyticsdemo_batch_id__c LIKE \'ECONDEV_DEMO_AF_%\'', logs);
deleteBySoql('outfunds__Funding_Request__c', 'SELECT Id FROM outfunds__Funding_Request__c WHERE analyticsdemo_batch_id__c LIKE \'ECONDEV_DEMO_FR_%\'', logs);
deleteBySoql('Opportunity', 'SELECT Id FROM Opportunity WHERE analyticsdemo_batch_id__c LIKE \'ECONDEV_DEMO_OPP_%\'', logs);
deleteBySoql('Site__c', 'SELECT Id FROM Site__c WHERE analyticsdemo_batch_id__c LIKE \'ECONDEV_DEMO_SITE_%\'', logs);
deleteBySoql('Contact', 'SELECT Id FROM Contact WHERE analyticsdemo_batch_id__c LIKE \'ECONDEV_DEMO_CONTACT_%\'', logs);
deleteBySoql('Account', 'SELECT Id FROM Account WHERE analyticsdemo_batch_id__c LIKE \'ECONDEV_DEMO_ACCOUNT_%\'', logs);

System.debug('ECONDEV_DEMO CLEANUP SUMMARY');
for (String line : logs) {
    System.debug(line);
}
