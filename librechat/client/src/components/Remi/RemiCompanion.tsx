import type { UseRemiCompanionOptions } from './useRemiCompanion';

type RemiCompanionProps = UseRemiCompanionOptions & {
  hideOnLanding?: boolean;
};

/** @deprecated Corner companion removed — use inline {@link RemiStreamCaret} in message stream. */
export function useRemiCompanionVisible(_hideOnLanding: boolean): boolean {
  return false;
}

export default function RemiCompanion(_props: RemiCompanionProps) {
  return null;
}
