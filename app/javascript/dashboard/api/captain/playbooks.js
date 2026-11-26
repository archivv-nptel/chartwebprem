/* global axios */
import ApiClient from '../ApiClient';

class CaptainPlaybooks extends ApiClient {
  constructor() {
    super('captain/playbooks', { accountScoped: true });
  }

  create(playbook) {
    return super.create({ playbook });
  }

  update(id, playbook) {
    return super.update(id, { playbook });
  }

  publish(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  runs(id) {
    return axios.get(`${this.url}/${id}/runs`);
  }

  execute(id, conversationId, context) {
    return axios.post(`${this.url}/${id}/execute`, {
      conversation_id: conversationId,
      dry_run: true,
      context,
    });
  }
}

export default new CaptainPlaybooks();
