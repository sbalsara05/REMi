import { cn } from '~/utils';
import BorderGlow, { type BorderGlowProps } from './BorderGlow';
import {
  REMI_BORDER_GLOW_PRESETS,
  REMI_GLOW_HSL,
  REMI_GRADIENT_COLORS,
  remiBorderGlowMode,
  type RemiBorderGlowVariant,
} from './remiBorderGlowTheme';
import './remiBorderGlow.css';

export type RemiBorderGlowProps = Omit<
  BorderGlowProps,
  'colors' | 'glowColor' | 'backgroundColor'
> & {
  variant?: RemiBorderGlowVariant;
  colors?: string[];
  glowColor?: string;
  backgroundColor?: string;
};

export default function RemiBorderGlow({
  variant = 'card',
  className,
  colors = [...REMI_GRADIENT_COLORS],
  glowColor = REMI_GLOW_HSL,
  backgroundColor = 'rgb(var(--rgb-surface-primary-alt) / 0.32)',
  animated,
  active,
  glowMode,
  borderRadius,
  glowRadius,
  edgeSensitivity,
  coneSpread,
  fillOpacity,
  ...props
}: RemiBorderGlowProps) {
  const preset = REMI_BORDER_GLOW_PRESETS[variant];

  return (
    <BorderGlow
      className={cn('remi-border-glow', `remi-border-glow--${variant}`, className)}
      colors={colors}
      glowColor={glowColor}
      backgroundColor={backgroundColor}
      glowMode={glowMode ?? remiBorderGlowMode(variant)}
      active={active}
      animated={animated ?? preset.animated ?? false}
      borderRadius={borderRadius ?? preset.borderRadius}
      glowRadius={glowRadius ?? preset.glowRadius}
      edgeSensitivity={edgeSensitivity ?? preset.edgeSensitivity}
      coneSpread={coneSpread ?? preset.coneSpread}
      fillOpacity={fillOpacity ?? preset.fillOpacity}
      {...props}
    />
  );
}
