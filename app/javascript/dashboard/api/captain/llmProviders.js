/* global axios */
import ApiClient from '../ApiClient';

class CaptainLlmProviders extends ApiClient {
  constructor() {
    super('captain/llm_providers', { accountScoped: true });
  }

  create(llmProvider) {
    return super.create({ llm_provider: llmProvider });
  }

  update(id, llmProvider) {
    return super.update(id, { llm_provider: llmProvider });
  }

  testConnection(id) {
    return axios.post(`${this.url}/${id}/test_connection`);
  }
}

export default new CaptainLlmProviders();
