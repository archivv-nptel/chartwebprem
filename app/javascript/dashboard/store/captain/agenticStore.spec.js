import { createPinia, setActivePinia } from 'pinia';
import ActionApprovalsAPI from 'dashboard/api/captain/actionApprovals';
import { useCaptainAgenticStore } from './agenticStore';

vi.mock('dashboard/api/captain/actionApprovals', () => ({
  default: { get: vi.fn(), approve: vi.fn(), reject: vi.fn() },
}));

describe('Captain approval state', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCaptainAgenticStore();
  });

  it('ignores an older list when switching conversations', async () => {
    const previous = Promise.withResolvers();
    ActionApprovalsAPI.get
      .mockReturnValueOnce(previous.promise)
      .mockResolvedValueOnce({ data: { payload: [{ id: 20 }] } });

    const loadingPrevious = store.fetchApprovals(1, 1);
    await store.fetchApprovals(1, 2);
    previous.resolve({ data: { payload: [{ id: 10 }] } });
    await loadingPrevious;

    expect(store.approvals).toEqual([{ id: 20 }]);
  });

  it('preserves a reviewed result when an in-flight list still marks it pending', async () => {
    const pending = { id: 10, status: 'pending' };
    const executed = { id: 10, status: 'executed' };
    const refresh = Promise.withResolvers();
    ActionApprovalsAPI.get
      .mockResolvedValueOnce({ data: { payload: [pending] } })
      .mockReturnValueOnce(refresh.promise);
    ActionApprovalsAPI.approve.mockResolvedValueOnce({ data: executed });

    await store.fetchApprovals(1, 1);
    const loadingRefresh = store.fetchApprovals(1, 1);
    await store.approveAction(10);
    refresh.resolve({ data: { payload: [pending] } });
    await loadingRefresh;

    expect(store.approvals).toEqual([executed]);
    expect(store.reviewedIds).toEqual([10]);
    expect(ActionApprovalsAPI.approve).toHaveBeenCalledWith(10, undefined);
  });

  it('clears review history when opening another account with the same conversation number', async () => {
    ActionApprovalsAPI.get
      .mockResolvedValueOnce({
        data: { payload: [{ id: 10, status: 'pending' }] },
      })
      .mockResolvedValueOnce({
        data: { payload: [{ id: 20, status: 'pending' }] },
      });
    ActionApprovalsAPI.reject.mockResolvedValueOnce({
      data: { id: 10, status: 'rejected' },
    });

    await store.fetchApprovals(1, 1);
    await store.rejectAction(10, 'Duplicate');
    expect(store.reviewedIds).toEqual([10]);

    await store.fetchApprovals(2, 1);
    expect(store.approvals).toEqual([{ id: 20, status: 'pending' }]);
    expect(store.reviewedIds).toEqual([]);
  });
});
