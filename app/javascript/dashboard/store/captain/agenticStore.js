import { defineStore } from 'pinia';
import ActionApprovalsAPI from 'dashboard/api/captain/actionApprovals';

export const useCaptainAgenticStore = defineStore('captainAgentic', {
  state: () => ({
    approvalScope: null,
    approvals: [],
    reviewedIds: [],
    approvalRequest: 0,
  }),

  actions: {
    async fetchApprovals(accountId, conversationId) {
      const scope = `${accountId}:${conversationId}`;
      if (scope !== this.approvalScope) this.clearApprovals();
      this.approvalScope = scope;
      this.approvalRequest += 1;
      const request = this.approvalRequest;
      const { data } = await ActionApprovalsAPI.get(conversationId);
      if (request === this.approvalRequest) this.approvals = data.payload;
    },

    clearApprovals() {
      this.approvalScope = null;
      this.approvals = [];
      this.reviewedIds = [];
      this.approvalRequest += 1;
    },

    replaceApproval(approval, scope) {
      if (scope !== this.approvalScope) return;
      this.approvalRequest += 1;
      if (!this.reviewedIds.includes(approval.id))
        this.reviewedIds.push(approval.id);
      this.approvals = this.approvals.map(item =>
        item.id === approval.id ? approval : item
      );
    },

    async approveAction(id, modifiedArguments) {
      const scope = this.approvalScope;
      const { data } = await ActionApprovalsAPI.approve(id, modifiedArguments);
      this.replaceApproval(data, scope);
    },

    async rejectAction(id, reason) {
      const scope = this.approvalScope;
      const { data } = await ActionApprovalsAPI.reject(id, reason);
      this.replaceApproval(data, scope);
    },
  },
});
