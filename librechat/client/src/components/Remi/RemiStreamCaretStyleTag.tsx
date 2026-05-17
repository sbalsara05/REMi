import { getRemiStreamCaretCss } from './remiStreamCaretCss';

/** Injects catalog-derived sprite keyframes for inline stream carets (::after). */
export default function RemiStreamCaretStyleTag() {
  return <style data-testid="remi-stream-caret-styles">{getRemiStreamCaretCss()}</style>;
}
