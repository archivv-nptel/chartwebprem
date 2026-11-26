/* global axios */
import ApiClient from '../ApiClient';

class CaptainSimulations extends ApiClient {
  constructor() {
    super('captain/simulations', { accountScoped: true });
  }

  show(id, page) {
    return axios.get(`${this.url}/${id}`, { params: { page } });
  }
}

export default new CaptainSimulations();
