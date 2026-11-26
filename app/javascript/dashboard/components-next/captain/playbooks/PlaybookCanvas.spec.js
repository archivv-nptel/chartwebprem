import { mount } from '@vue/test-utils';
import PlaybookCanvas from './PlaybookCanvas.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const ADD_NODE = 'CAPTAIN.AGENTIC.PLAYBOOKS.ADD_NODE';
const SAVE_GRAPH = 'CAPTAIN.AGENTIC.PLAYBOOKS.SAVE_GRAPH';

function mountCanvas(graph) {
  return mount(PlaybookCanvas, {
    props: { graph },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: {
          props: ['label'],
          template: '<button type="button">{{ label }}</button>',
        },
      },
    },
  });
}

function button(wrapper, label) {
  return wrapper.findAll('button').find(item => item.text() === label);
}

describe('Captain playbook editor', () => {
  it('adds the unallocated branch when attaching a node to a condition', async () => {
    const wrapper = mountCanvas({
      nodes: [
        {
          id: 'amount',
          type: 'condition',
          config: { field: 'amount', operator: 'lte', value: 10 },
        },
        { id: 'eligible', type: 'reply', config: { template: 'Eligible' } },
      ],
      edges: [{ source: 'amount', target: 'eligible', label: 'true' }],
    });

    await wrapper.findAll('select')[1].setValue('amount');
    await button(wrapper, ADD_NODE).trigger('click');
    await button(wrapper, SAVE_GRAPH).trigger('click');

    const [[graph]] = wrapper.emitted('save');
    const newNode = graph.nodes.at(-1);
    expect(newNode.type).toBe('reply');
    expect(graph.edges.at(-1)).toEqual({
      source: 'amount',
      target: newNode.id,
      label: 'false',
    });
  });

  it('keeps an invalid draft editable without submitting it', async () => {
    const wrapper = mountCanvas({ nodes: [], edges: [] });
    await wrapper.get('textarea').setValue('{"nodes":');
    await button(wrapper, SAVE_GRAPH).trigger('click');

    expect(wrapper.get('[role="alert"]').text()).toBe(
      'CAPTAIN.AGENTIC.PLAYBOOKS.INVALID_GRAPH'
    );
    expect(wrapper.emitted('save')).toBeUndefined();
  });
});
