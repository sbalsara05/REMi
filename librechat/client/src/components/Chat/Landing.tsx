import { useMemo, useCallback, useState, useEffect, useRef } from 'react';
import { easings } from '@react-spring/web';
import { BirthdayIcon, TooltipAnchor, SplitText } from '@librechat/client';
import { useChatContext, useAgentsMapContext, useAssistantsMapContext } from '~/Providers';
import { useGetEndpointsQuery, useGetStartupConfig } from '~/data-provider';
import ConvoIcon from '~/components/Endpoints/ConvoIcon';
import { RemiBorderGlow } from '~/components/BorderGlow';
import RemiPlayfulMouse from '~/components/Remi/RemiPlayfulMouse';
import { useLocalize, useAuthContext } from '~/hooks';
import { getEntity } from '~/utils';

const REMI_DISPLAY_NAME = 'Remi';

const entityIconContainerClassName =
  'shadow-stroke relative flex h-full w-full items-center justify-center overflow-hidden rounded-full bg-white dark:bg-presentation dark:text-white text-black dark:after:shadow-none';

function getTextSizeClass(text: string | undefined | null) {
  if (!text) {
    return 'text-xl sm:text-2xl';
  }

  if (text.length < 40) {
    return 'text-2xl sm:text-4xl';
  }

  if (text.length < 70) {
    return 'text-xl sm:text-2xl';
  }

  return 'text-lg sm:text-md';
}

export default function Landing() {
  const { conversation } = useChatContext();
  const agentsMap = useAgentsMapContext();
  const assistantMap = useAssistantsMapContext();
  const { data: startupConfig } = useGetStartupConfig();
  const { data: endpointsConfig } = useGetEndpointsQuery();
  const { user } = useAuthContext();
  const localize = useLocalize();

  const [textHasMultipleLines, setTextHasMultipleLines] = useState(false);
  const [lineCount, setLineCount] = useState(1);
  const [contentHeight, setContentHeight] = useState(0);
  const contentRef = useRef<HTMLDivElement>(null);

  const { entity, isAgent, isAssistant } = getEntity({
    endpoint: conversation?.endpoint,
    agentsMap,
    assistantMap,
    agent_id: conversation?.agent_id,
    assistant_id: conversation?.assistant_id,
  });

  const name = entity?.name ?? '';
  const description = (entity?.description || conversation?.greeting) ?? '';
  const showEntityBranding = Boolean(((isAgent || isAssistant) && name) || name);
  const landingTitle = showEntityBranding ? name : REMI_DISPLAY_NAME;

  const getGreeting = useCallback(() => {
    if (typeof startupConfig?.interface?.customWelcome === 'string') {
      const customWelcome = startupConfig.interface.customWelcome;
      if (user?.name && customWelcome.includes('{{user.name}}')) {
        return customWelcome.replace(/{{user.name}}/g, user.name);
      }
      return customWelcome;
    }

    const now = new Date();
    const hours = now.getHours();
    const dayOfWeek = now.getDay();
    const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

    if (hours >= 0 && hours < 5) {
      return localize('com_ui_late_night');
    }
    if (hours < 12) {
      if (isWeekend) {
        return localize('com_ui_weekend_morning');
      }
      return localize('com_ui_good_morning');
    }
    if (hours < 17) {
      return localize('com_ui_good_afternoon');
    }
    return localize('com_ui_good_evening');
  }, [localize, startupConfig?.interface?.customWelcome, user?.name]);

  const handleLineCountChange = useCallback((count: number) => {
    setTextHasMultipleLines(count > 1);
    setLineCount(count);
  }, []);

  useEffect(() => {
    if (contentRef.current) {
      setContentHeight(contentRef.current.offsetHeight);
    }
  }, [lineCount, description]);

  const getDynamicMargin = useMemo(() => {
    if (contentHeight > 200) {
      return 'mb-2';
    }
    if (contentHeight > 150 || (description && description.length > 100)) {
      return 'mb-1';
    }
    return '';
  }, [contentHeight, description]);

  const greetingText =
    typeof startupConfig?.interface?.customWelcome === 'string'
      ? getGreeting()
      : getGreeting() + (user?.name ? ', ' + user.name : '');

  return (
    <div
      className={`chat-landing-hero flex w-full transform-gpu flex-col items-center justify-center transition-all duration-200 ${getDynamicMargin}`}
    >
      <RemiBorderGlow
        variant="card"
        className="remi-radius-card max-w-lg shrink-0"
        innerClassName="flex flex-col items-center gap-0 p-4 sm:p-6"
      >
        <div ref={contentRef} className="flex w-full flex-col items-center gap-0">
          <div className="relative mb-3 flex justify-center">
            <RemiPlayfulMouse profile="hero" />
            {startupConfig?.showBirthdayIcon && (
              <TooltipAnchor
                className="absolute bottom-0 right-0"
                description={localize('com_ui_happy_birthday')}
                aria-label={localize('com_ui_happy_birthday')}
              >
                <BirthdayIcon />
              </TooltipAnchor>
            )}
          </div>
          <div className="mouse-stripe-divider mx-auto mb-4 w-32 max-w-full shrink-0" aria-hidden />
          {showEntityBranding && (
            <div className="relative mb-2 size-10 shrink-0">
              <ConvoIcon
                agentsMap={agentsMap}
                assistantMap={assistantMap}
                conversation={conversation}
                endpointsConfig={endpointsConfig ?? {}}
                containerClassName={entityIconContainerClassName}
                context="landing"
                className="h-2/3 w-2/3 text-black dark:text-white"
                size={41}
              />
            </div>
          )}
          <div className="flex flex-col items-center gap-0 p-2 text-center">
            <SplitText
              key={`split-text-${landingTitle}`}
              text={landingTitle}
              className={`${getTextSizeClass(landingTitle)} font-medium text-text-primary`}
              delay={50}
              textAlign="center"
              animationFrom={{ opacity: 0, transform: 'translate3d(0,50px,0)' }}
              animationTo={{ opacity: 1, transform: 'translate3d(0,0,0)' }}
              easing={easings.easeOutCubic}
              threshold={0}
              rootMargin="0px"
              onLineCountChange={handleLineCountChange}
            />
            {!showEntityBranding && (
              <p className="animate-fadeIn mt-2 max-w-sm text-center text-sm font-normal text-text-secondary">
                {greetingText}
              </p>
            )}
          </div>
          {description && (
            <div className="animate-fadeIn mt-4 max-w-md text-center text-sm font-normal text-text-primary">
              {description}
            </div>
          )}
        </div>
      </RemiBorderGlow>
    </div>
  );
}
