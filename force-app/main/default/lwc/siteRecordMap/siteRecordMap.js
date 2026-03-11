import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getSiteMapData from '@salesforce/apex/SiteMapController.getSiteMapData';

export default class SiteRecordMap extends LightningElement {
    @api recordId;
    // Developer note:
    // Keep debug hidden in production. Set to true in App Builder if you need diagnostics.
    @api showDebug = false;

    pageRecordId;
    urlRecordId;

    // Developer note:
    // Pull record context from page state for containers where @api recordId isn't passed.
    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        this.pageRecordId = pageRef?.state?.recordId || pageRef?.attributes?.recordId || null;
    }

    connectedCallback() {
        // Developer note:
        // URL fallback for routes like /lightning/r/Site__c/<id>/view.
        const path = window?.location?.pathname || '';
        const match = path.match(/\/([a-zA-Z0-9]{15,18})\/(view|edit)$/);
        this.urlRecordId = match ? match[1] : null;
    }

    get effectiveRecordId() {
        return this.recordId || this.pageRecordId || this.urlRecordId;
    }

    get hasRecordContext() {
        return !!this.effectiveRecordId;
    }

    // Developer note:
    // Apex wire is used intentionally to avoid LDS quirks in some record page layouts.
    @wire(getSiteMapData, { siteId: '$effectiveRecordId' })
    siteData;

    get hasError() {
        return !!this.siteData.error;
    }

    get hasData() {
        return !!this.siteData.data;
    }

    get statusLabel() {
        if (this.hasMarker) return 'Mapped';
        if (this.hasError) return 'Load Error';
        if (!this.hasRecordContext) return 'No Context';
        return 'Awaiting Data';
    }

    get statusClass() {
        if (this.hasMarker) return 'status status-success';
        if (this.hasError) return 'status status-error';
        return 'status status-neutral';
    }

    get hasMarker() {
        return this.mapMarkers.length > 0;
    }

    get mapMarkers() {
        const data = this.siteData.data;
        if (!data) {
            return [];
        }

        // Developer note:
        // Coordinate precedence: verified -> compound geolocation -> base lat/lng.
        const bestLat = this.firstNonNull([data.verifiedLatitude, data.geoLatitude, data.latitude]);
        const bestLng = this.firstNonNull([data.verifiedLongitude, data.geoLongitude, data.longitude]);
        const latNum = Number.parseFloat(bestLat);
        const lngNum = Number.parseFloat(bestLng);

        const marker = {
            title: data.name || 'Site',
            description: this.addressLabel(data)
        };

        if (Number.isFinite(latNum) && Number.isFinite(lngNum)) {
            marker.location = {
                Latitude: latNum,
                Longitude: lngNum
            };
        } else if (data.street || data.city || data.state || data.postalCode) {
            // Developer note:
            // Address fallback still allows the map to resolve a point.
            marker.location = {
                Street: data.street,
                City: data.city,
                State: data.state,
                PostalCode: data.postalCode
            };
        } else {
            return [];
        }

        return [marker];
    }

    get mapCenter() {
        return this.hasMarker ? this.mapMarkers[0].location : null;
    }

    get mapTitle() {
        return this.siteData.data?.name || 'Site Location';
    }

    get locationLine() {
        return this.hasData ? this.addressLabel(this.siteData.data) : '';
    }

    get coordinateLine() {
        const data = this.siteData.data;
        if (!data) return '';

        const bestLat = this.firstNonNull([data.verifiedLatitude, data.geoLatitude, data.latitude]);
        const bestLng = this.firstNonNull([data.verifiedLongitude, data.geoLongitude, data.longitude]);
        if (bestLat === null || bestLng === null) return 'Coordinates unavailable';

        return `Lat ${Number(bestLat).toFixed(6)}  |  Lng ${Number(bestLng).toFixed(6)}`;
    }

    get debugInfo() {
        const data = this.siteData.data;
        if (!data) {
            return `recordId=${this.effectiveRecordId || 'none'} data=none`;
        }
        const bestLat = this.firstNonNull([data.verifiedLatitude, data.geoLatitude, data.latitude]);
        const bestLng = this.firstNonNull([data.verifiedLongitude, data.geoLongitude, data.longitude]);
        return `recordId=${this.effectiveRecordId || 'none'} lat=${bestLat ?? 'null'} lng=${bestLng ?? 'null'}`;
    }

    firstNonNull(values) {
        for (const v of values) {
            if (v !== null && v !== undefined && v !== '') {
                return v;
            }
        }
        return null;
    }

    addressLabel(data) {
        const street = data.street || '';
        const city = data.city || '';
        const state = data.state || '';
        const zip = data.postalCode || '';

        return [street, [city, state, zip].filter(Boolean).join(' ')].filter(Boolean).join(', ');
    }
}
