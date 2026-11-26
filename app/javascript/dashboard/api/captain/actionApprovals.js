/* global axios */
import ApiClient from '../ApiClient';

class CaptainActionApprovals extends ApiClient {
  constructor() {
    super('captain/action_approvals', { accountScoped: true });
  }

  get(conversationId) {
    return axios.get(this.url, { params: { conversation_id: conversationId } });
  }

  approve(id, modifiedArguments) {
    return axios.post(`${this.url}/${id}/approve`, {
      modified_arguments: modifiedArguments,
    });
  }

  reject(id, reason) {
    return axios.post(`${this.url}/${id}/reject`, { reason });
  }
}

export default new CaptainActionApprovals();
