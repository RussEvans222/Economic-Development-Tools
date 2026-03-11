public with sharing class SiteMapController {
    // Developer note:
    // DTO returned to LWC to avoid exposing raw SObject shape in the UI layer.
    public class SiteMapData {
        @AuraEnabled public Id siteId;
        @AuraEnabled public String name;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public Decimal verifiedLatitude;
        @AuraEnabled public Decimal verifiedLongitude;
        @AuraEnabled public Decimal geoLatitude;
        @AuraEnabled public Decimal geoLongitude;
    }

    @AuraEnabled(cacheable=true)
    public static SiteMapData getSiteMapData(Id siteId) {
        if (siteId == null) return null;

        // Developer note:
        // Pull all coordinate variants so the LWC can use precedence/fallback logic.
        Site__c site = [
            SELECT Id,
                   Name,
                   Street_Address__c,
                   City__c,
                   State__c,
                   Postal_Zip_Code__c,
                   Latitude__c,
                   Longitude__c,
                   Verified_Latitude__c,
                   Verified_Longitude__c,
                   Site_Geolocation__Latitude__s,
                   Site_Geolocation__Longitude__s
            FROM Site__c
            WHERE Id = :siteId
            LIMIT 1
        ];

        SiteMapData out = new SiteMapData();
        // Developer note:
        // Explicit mapping keeps API names centralized in Apex and easier to refactor.
        out.siteId = site.Id;
        out.name = site.Name;
        out.street = site.Street_Address__c;
        out.city = site.City__c;
        out.state = site.State__c;
        out.postalCode = site.Postal_Zip_Code__c;
        out.latitude = site.Latitude__c;
        out.longitude = site.Longitude__c;
        out.verifiedLatitude = site.Verified_Latitude__c;
        out.verifiedLongitude = site.Verified_Longitude__c;
        out.geoLatitude = site.Site_Geolocation__Latitude__s;
        out.geoLongitude = site.Site_Geolocation__Longitude__s;
        return out;
    }
}
