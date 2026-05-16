import {
  remiContext,
  remiHandoff,
  remiInteraction,
  remiInteractions,
} from '../src/api-endpoints';

describe('REMi API endpoints', () => {
  it('builds the interactions list URL without query params', () => {
    expect(remiInteractions()).toBe('/api/remi/interactions');
  });

  it('builds the interactions list URL with cursor and limit', () => {
    expect(remiInteractions('1700000000000', 50)).toBe(
      '/api/remi/interactions?cursor=1700000000000&limit=50',
    );
  });

  it('builds interaction, context, and handoff URLs', () => {
    expect(remiInteraction('abc-123')).toBe('/api/remi/interactions/abc-123');
    expect(remiContext()).toBe('/api/remi/context');
    expect(remiHandoff()).toBe('/api/remi/handoff');
  });
});
