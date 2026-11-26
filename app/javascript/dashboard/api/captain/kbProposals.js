/* global axios */
import ApiClient from '../ApiClient';

class CaptainKbProposals extends ApiClient {
  constructor() {
    super('captain/kb_proposals', { accountScoped: true });
  }

  get(page) {
    return axios.get(this.url, { params: { page } });
  }

  update(id, proposal) {
    return super.update(id, { kb_proposal: proposal });
  }

  merge(id) {
    return axios.post(`${this.url}/${id}/merge`);
  }

  reject(id) {
    return axios.post(`${this.url}/${id}/reject`);
  }
}

export default new CaptainKbProposals();
