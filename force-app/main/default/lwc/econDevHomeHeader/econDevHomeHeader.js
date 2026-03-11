import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getHomeSnapshot from '@salesforce/apex/EconDevHomeHeaderController.getHomeSnapshot';

export default class EconDevHomeHeader extends NavigationMixin(LightningElement) {
    wiredSnapshotResult;
    snapshot;
    error;

    // Developer note:
    // Wire allows instant load plus manual refresh via refreshApex.
    @wire(getHomeSnapshot)
    wiredSnapshot(value) {
        this.wiredSnapshotResult = value;
        const { data, error } = value;
        this.snapshot = data;
        this.error = error;
    }

    get hasData() {
        return !!this.snapshot;
    }

    get hasError() {
        return !!this.error;
    }

    get openOpportunityCount() {
        return this.snapshot?.openOpportunityCount ?? 0;
    }

    get openPipelineAmount() {
        return this.snapshot?.openPipelineAmount ?? 0;
    }

    get topOpenStage() {
        return this.snapshot?.topOpenStage ?? 'N/A';
    }

    get mansfieldSiteCount() {
        return this.snapshot?.mansfieldSiteCount ?? 0;
    }

    get mansfieldMappedSiteCount() {
        return this.snapshot?.mansfieldMappedSiteCount ?? 0;
    }

    get inFlightFundingRequestCount() {
        return this.snapshot?.inFlightFundingRequestCount ?? 0;
    }

    get inFlightFundingRequestedAmount() {
        return this.snapshot?.inFlightFundingRequestedAmount ?? 0;
    }

    get totalAvailableFundsAmount() {
        return this.snapshot?.totalAvailableFundsAmount ?? 0;
    }

    get totalAwardedFundsAmount() {
        return this.snapshot?.totalAwardedFundsAmount ?? 0;
    }

    get acceptedBackgroundCheckCount() {
        return this.snapshot?.acceptedBackgroundCheckCount ?? 0;
    }

    get meetingsNext7Days() {
        return this.snapshot?.meetingsNext7Days ?? 0;
    }

    get generatedAt() {
        return this.snapshot?.generatedAt;
    }

    // Developer note:
    // Build UI-ready chart rows with percentage widths for simple native bar charts.
    get stageChartRows() {
        const rows = this.snapshot?.openStageMetrics || [];
        const max = rows.reduce((m, r) => Math.max(m, r.countValue || 0), 0);
        return rows.map((r) => {
            const pct = max > 0 ? Math.max(8, Math.round(((r.countValue || 0) / max) * 100)) : 0;
            return {
                label: r.label || 'Unknown',
                count: r.countValue || 0,
                amount: r.amountValue || 0,
                barStyle: `width:${pct}%;`
            };
        });
    }

    get fundingChartRows() {
        const rows = this.snapshot?.fundingStatusMetrics || [];
        const max = rows.reduce((m, r) => Math.max(m, r.countValue || 0), 0);
        return rows.map((r) => {
            const pct = max > 0 ? Math.max(8, Math.round(((r.countValue || 0) / max) * 100)) : 0;
            return {
                label: r.label || 'Unknown',
                count: r.countValue || 0,
                amount: r.amountValue || 0,
                barStyle: `width:${pct}%;`
            };
        });
    }

    get hasStageChartData() {
        return this.stageChartRows.length > 0;
    }

    get hasFundingChartData() {
        return this.fundingChartRows.length > 0;
    }

    // Developer note:
    // Two-bar comparison for Funding Program available funds vs awarded funds.
    get fundingComparisonRows() {
        const rows = [
            { label: 'Available Funds', amount: this.totalAvailableFundsAmount, fillClass: 'chart-fill comparison-total-fill' },
            { label: 'Total Awarded Funds', amount: this.totalAwardedFundsAmount, fillClass: 'chart-fill comparison-awarded-fill' }
        ];
        const max = rows.reduce((m, r) => Math.max(m, r.amount || 0), 0);
        return rows.map((r) => {
            const pct = max > 0 ? Math.max(8, Math.round(((r.amount || 0) / max) * 100)) : 0;
            return {
                ...r,
                barStyle: `width:${pct}%;`
            };
        });
    }

    async handleRefresh() {
        if (this.wiredSnapshotResult) {
            await refreshApex(this.wiredSnapshotResult);
        }
    }

    // Developer note:
    // Quick actions provide common navigation shortcuts for admins/developers.
    handleNewOpportunity() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Opportunity', actionName: 'new' }
        });
    }

    handleNewSite() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Site__c', actionName: 'new' }
        });
    }

    handleFundingRequests() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'outfunds__Funding_Request__c', actionName: 'list' },
            state: { filterName: 'Recent' }
        });
    }

    handleMansfieldSites() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Site__c', actionName: 'list' },
            state: { filterName: 'Recent' }
        });
    }

    handleSetupSiteObject() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: '/lightning/setup/ObjectManager/Site__c/Details/view' }
        });
    }

    handleSetupApexClasses() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: '/lightning/setup/ApexClasses/home' }
        });
    }

    handleSetupDebugLogs() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: '/lightning/setup/ApexLogs/home' }
        });
    }
}
