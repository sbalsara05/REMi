import { ThemeSelector } from '@librechat/client';
import { TStartupConfig } from 'librechat-data-provider';
import { ErrorMessage } from '~/components/Auth/ErrorMessage';
import RemiPlayfulMouse from '~/components/Remi/RemiPlayfulMouse';
import RemiAmbient from '~/components/Glass/RemiAmbient';
import { TranslationKeys, useLocalize } from '~/hooks';
import SocialLoginRender from './SocialLoginRender';
import { BlinkAnimation } from './BlinkAnimation';
import { Banner } from '../Banners';
import Footer from './Footer';

function AuthLayout({
  children,
  header,
  isFetching,
  startupConfig,
  startupConfigError,
  pathname,
  error,
}: {
  children: React.ReactNode;
  header: React.ReactNode;
  isFetching: boolean;
  startupConfig: TStartupConfig | null | undefined;
  startupConfigError: unknown | null | undefined;
  pathname: string;
  error: TranslationKeys | null;
}) {
  const localize = useLocalize();
  const appTitle = startupConfig?.appTitle ?? 'REMi';

  const hasStartupConfigError = startupConfigError !== null && startupConfigError !== undefined;
  const DisplayError = () => {
    if (hasStartupConfigError) {
      return (
        <div className="mx-auto sm:max-w-sm">
          <ErrorMessage>{localize('com_auth_error_login_server')}</ErrorMessage>
        </div>
      );
    }
    if (error === 'com_auth_error_invalid_reset_token') {
      return (
        <div className="mx-auto sm:max-w-sm">
          <ErrorMessage>
            {localize('com_auth_error_invalid_reset_token')}{' '}
            <a className="font-semibold text-green-600 hover:underline" href="/forgot-password">
              {localize('com_auth_click_here')}
            </a>{' '}
            {localize('com_auth_to_try_again')}
          </ErrorMessage>
        </div>
      );
    }
    if (error != null && error) {
      return (
        <div className="mx-auto sm:max-w-sm">
          <ErrorMessage>{localize(error)}</ErrorMessage>
        </div>
      );
    }
    return null;
  };

  return (
    <div className="relative flex min-h-screen flex-col bg-[#0a0a0f] text-text-primary">
      <RemiAmbient />
      <Banner />
      <BlinkAnimation active={isFetching}>
        <div className="relative z-[1] mt-8 flex flex-col items-center gap-2">
          <RemiPlayfulMouse
            profile="hero"
            title={localize('com_ui_logo', { 0: appTitle })}
            className="scale-75 sm:scale-90"
          />
          <span className="text-sm font-semibold tracking-[0.2em] text-text-primary">{appTitle}</span>
        </div>
      </BlinkAnimation>
      <DisplayError />
      <div className="absolute bottom-0 left-0 z-[1] md:m-4">
        <ThemeSelector />
      </div>

      <main className="relative z-[1] flex flex-grow items-center justify-center px-4">
        <div className="glass-modal remi-radius-card w-authPageWidth overflow-hidden px-6 py-4 sm:max-w-md">
          {!hasStartupConfigError && !isFetching && header && (
            <h1
              className="mb-4 text-center text-3xl font-semibold text-text-primary"
              style={{ userSelect: 'none' }}
            >
              {header}
            </h1>
          )}
          {children}
          {!pathname.includes('2fa') &&
            (pathname.includes('login') || pathname.includes('register')) && (
              <SocialLoginRender startupConfig={startupConfig} />
            )}
        </div>
      </main>
      <Footer startupConfig={startupConfig} />
    </div>
  );
}

export default AuthLayout;
