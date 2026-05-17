import { memo } from 'react';
import RemiStreamCaret from '~/components/Remi/RemiStreamCaret';
import '~/components/Remi/remiStreamCaret.css';

/** Streaming cursor placeholder — no bottom margin to match Container's structure and prevent CLS */
const EmptyTextPart = memo(() => {
  return (
    <div className="text-message flex min-h-[20px] flex-col items-start gap-3 overflow-visible">
      <div className="markdown prose dark:prose-invert light w-full break-words dark:text-gray-100">
        <div className="submitting remi-stream-caret-slot">
          <RemiStreamCaret />
        </div>
      </div>
    </div>
  );
});

export default EmptyTextPart;
