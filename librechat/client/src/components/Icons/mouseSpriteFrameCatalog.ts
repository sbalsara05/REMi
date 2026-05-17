/** Auto-labeled Foozle mouse sheet frames (64×48 cells). Regenerate via scripts/label-mouse-spritesheet.py */

export type FrameViewport = {
  w: number;
  h: number;
  ox: number;
  oy: number;
};

export type SheetFrameLabel = {
  row: number;
  col: number;
  rowName: string;
  label: string;
  viewport: FrameViewport;
};

export const MOUSE_SHEET_ROW_NAMES = ["idle_lunge", "run", "jump", "double_jump", "light_dash", "edge_grab", "wall_slide", "light_attack_1", "light_attack_2", "light_attack_3", "heavy_attack", "hurt", "death"] as const;

export const MOUSE_SHEET_FRAMES: SheetFrameLabel[] = [
  { row: 0, col: 0, rowName: 'idle_lunge', label: 'lunge_0', viewport: { w: 23, h: 32, ox: 20, oy: 16 } },
  { row: 0, col: 1, rowName: 'idle_lunge', label: 'lunge_1', viewport: { w: 23, h: 32, ox: 20, oy: 16 } },
  { row: 0, col: 2, rowName: 'idle_lunge', label: 'lunge_2', viewport: { w: 23, h: 31, ox: 20, oy: 17 } },
  { row: 0, col: 3, rowName: 'idle_lunge', label: 'lunge_3', viewport: { w: 23, h: 29, ox: 20, oy: 19 } },
  { row: 0, col: 4, rowName: 'idle_lunge', label: 'lunge_4', viewport: { w: 22, h: 28, ox: 21, oy: 20 } },
  { row: 0, col: 5, rowName: 'idle_lunge', label: 'lunge_5', viewport: { w: 22, h: 29, ox: 21, oy: 19 } },
  { row: 0, col: 6, rowName: 'idle_lunge', label: 'lunge_6', viewport: { w: 22, h: 30, ox: 21, oy: 18 } },
  { row: 1, col: 0, rowName: 'run', label: 'run_0', viewport: { w: 23, h: 29, ox: 20, oy: 19 } },
  { row: 1, col: 1, rowName: 'run', label: 'run_1', viewport: { w: 23, h: 29, ox: 20, oy: 19 } },
  { row: 1, col: 2, rowName: 'run', label: 'run_2', viewport: { w: 22, h: 29, ox: 21, oy: 16 } },
  { row: 1, col: 3, rowName: 'run', label: 'run_3', viewport: { w: 23, h: 32, ox: 20, oy: 16 } },
  { row: 1, col: 4, rowName: 'run', label: 'run_4', viewport: { w: 23, h: 29, ox: 20, oy: 19 } },
  { row: 1, col: 5, rowName: 'run', label: 'run_5', viewport: { w: 24, h: 29, ox: 19, oy: 19 } },
  { row: 1, col: 6, rowName: 'run', label: 'run_6', viewport: { w: 24, h: 29, ox: 19, oy: 16 } },
  { row: 1, col: 7, rowName: 'run', label: 'run_7', viewport: { w: 24, h: 32, ox: 19, oy: 16 } },
  { row: 2, col: 0, rowName: 'jump', label: 'jump_0', viewport: { w: 24, h: 35, ox: 19, oy: 13 } },
  { row: 2, col: 1, rowName: 'jump', label: 'jump_1', viewport: { w: 22, h: 30, ox: 21, oy: 11 } },
  { row: 2, col: 2, rowName: 'jump', label: 'jump_2', viewport: { w: 21, h: 29, ox: 22, oy: 10 } },
  { row: 2, col: 3, rowName: 'jump', label: 'jump_3', viewport: { w: 20, h: 32, ox: 23, oy: 11 } },
  { row: 2, col: 4, rowName: 'jump', label: 'jump_4', viewport: { w: 19, h: 35, ox: 24, oy: 13 } },
  { row: 2, col: 5, rowName: 'jump', label: 'jump_5', viewport: { w: 19, h: 28, ox: 24, oy: 20 } },
  { row: 3, col: 0, rowName: 'double_jump', label: 'dj_stand', viewport: { w: 22, h: 32, ox: 21, oy: 11 } },
  { row: 3, col: 1, rowName: 'double_jump', label: 'dj_stride', viewport: { w: 24, h: 26, ox: 19, oy: 7 } },
  { row: 3, col: 2, rowName: 'double_jump', label: 'dj_roll_1', viewport: { w: 22, h: 21, ox: 22, oy: 7 } },
  { row: 3, col: 3, rowName: 'double_jump', label: 'dj_roll_2', viewport: { w: 21, h: 22, ox: 24, oy: 7 } },
  { row: 3, col: 4, rowName: 'double_jump', label: 'dj_roll_3', viewport: { w: 22, h: 21, ox: 21, oy: 10 } },
  { row: 3, col: 5, rowName: 'double_jump', label: 'dj_stand_2', viewport: { w: 21, h: 29, ox: 22, oy: 13 } },
  { row: 3, col: 6, rowName: 'double_jump', label: 'dj_stand_3', viewport: { w: 19, h: 35, ox: 24, oy: 13 } },
  { row: 3, col: 7, rowName: 'double_jump', label: 'dj_stand_low', viewport: { w: 19, h: 28, ox: 24, oy: 20 } },
  { row: 4, col: 0, rowName: 'light_dash', label: 'dash_idle', viewport: { w: 23, h: 31, ox: 20, oy: 17 } },
  { row: 4, col: 1, rowName: 'light_dash', label: 'dash_1', viewport: { w: 26, h: 28, ox: 17, oy: 20 } },
  { row: 4, col: 2, rowName: 'light_dash', label: 'dash_2', viewport: { w: 28, h: 27, ox: 15, oy: 19 } },
  { row: 4, col: 3, rowName: 'light_dash', label: 'dash_3', viewport: { w: 26, h: 29, ox: 17, oy: 19 } },
  { row: 5, col: 0, rowName: 'edge_grab', label: 'edge_0', viewport: { w: 20, h: 29, ox: 23, oy: 17 } },
  { row: 5, col: 1, rowName: 'edge_grab', label: 'edge_1', viewport: { w: 22, h: 30, ox: 21, oy: 16 } },
  { row: 5, col: 2, rowName: 'edge_grab', label: 'edge_2', viewport: { w: 22, h: 30, ox: 21, oy: 16 } },
  { row: 5, col: 3, rowName: 'edge_grab', label: 'edge_3', viewport: { w: 20, h: 28, ox: 23, oy: 18 } },
  { row: 5, col: 4, rowName: 'edge_grab', label: 'edge_4', viewport: { w: 19, h: 28, ox: 24, oy: 18 } },
  { row: 6, col: 0, rowName: 'wall_slide', label: 'wall_0', viewport: { w: 19, h: 32, ox: 24, oy: 14 } },
  { row: 6, col: 1, rowName: 'wall_slide', label: 'wall_1', viewport: { w: 18, h: 33, ox: 25, oy: 13 } },
  { row: 6, col: 2, rowName: 'wall_slide', label: 'wall_2', viewport: { w: 17, h: 31, ox: 26, oy: 14 } },
  { row: 6, col: 3, rowName: 'wall_slide', label: 'wall_3', viewport: { w: 18, h: 32, ox: 25, oy: 13 } },
  { row: 7, col: 0, rowName: 'light_attack_1', label: 'r7c0', viewport: { w: 26, h: 27, ox: 22, oy: 21 } },
  { row: 7, col: 1, rowName: 'light_attack_1', label: 'r7c1', viewport: { w: 37, h: 27, ox: 22, oy: 21 } },
  { row: 7, col: 2, rowName: 'light_attack_1', label: 'r7c2', viewport: { w: 37, h: 26, ox: 22, oy: 22 } },
  { row: 7, col: 3, rowName: 'light_attack_1', label: 'r7c3', viewport: { w: 37, h: 25, ox: 22, oy: 23 } },
  { row: 7, col: 4, rowName: 'light_attack_1', label: 'r7c4', viewport: { w: 39, h: 26, ox: 20, oy: 22 } },
  { row: 7, col: 5, rowName: 'light_attack_1', label: 'r7c5', viewport: { w: 39, h: 27, ox: 20, oy: 21 } },
  { row: 7, col: 6, rowName: 'light_attack_1', label: 'r7c6', viewport: { w: 39, h: 27, ox: 20, oy: 21 } },
  { row: 7, col: 7, rowName: 'light_attack_1', label: 'r7c7', viewport: { w: 37, h: 27, ox: 22, oy: 21 } },
  { row: 7, col: 8, rowName: 'light_attack_1', label: 'r7c8', viewport: { w: 37, h: 26, ox: 22, oy: 22 } },
  { row: 7, col: 9, rowName: 'light_attack_1', label: 'r7c9', viewport: { w: 37, h: 25, ox: 22, oy: 23 } },
  { row: 8, col: 0, rowName: 'light_attack_2', label: 'r8c0', viewport: { w: 23, h: 31, ox: 20, oy: 17 } },
  { row: 8, col: 1, rowName: 'light_attack_2', label: 'r8c1', viewport: { w: 41, h: 27, ox: 18, oy: 21 } },
  { row: 8, col: 2, rowName: 'light_attack_2', label: 'r8c2', viewport: { w: 42, h: 26, ox: 17, oy: 20 } },
  { row: 8, col: 3, rowName: 'light_attack_2', label: 'r8c3', viewport: { w: 39, h: 28, ox: 20, oy: 20 } },
  { row: 8, col: 4, rowName: 'light_attack_2', label: 'r8c4', viewport: { w: 37, h: 28, ox: 22, oy: 20 } },
  { row: 9, col: 0, rowName: 'light_attack_3', label: 'r9c0', viewport: { w: 29, h: 26, ox: 22, oy: 22 } },
  { row: 9, col: 1, rowName: 'light_attack_3', label: 'r9c1', viewport: { w: 28, h: 26, ox: 22, oy: 22 } },
  { row: 9, col: 2, rowName: 'light_attack_3', label: 'r9c2', viewport: { w: 43, h: 27, ox: 17, oy: 21 } },
  { row: 9, col: 3, rowName: 'light_attack_3', label: 'r9c3', viewport: { w: 46, h: 27, ox: 15, oy: 19 } },
  { row: 9, col: 4, rowName: 'light_attack_3', label: 'r9c4', viewport: { w: 47, h: 26, ox: 14, oy: 18 } },
  { row: 9, col: 5, rowName: 'light_attack_3', label: 'r9c5', viewport: { w: 41, h: 28, ox: 20, oy: 20 } },
  { row: 9, col: 6, rowName: 'light_attack_3', label: 'r9c6', viewport: { w: 35, h: 27, ox: 22, oy: 21 } },
  { row: 10, col: 0, rowName: 'heavy_attack', label: 'r10c0', viewport: { w: 29, h: 27, ox: 22, oy: 21 } },
  { row: 10, col: 1, rowName: 'heavy_attack', label: 'r10c1', viewport: { w: 30, h: 33, ox: 11, oy: 6 } },
  { row: 10, col: 2, rowName: 'heavy_attack', label: 'r10c2', viewport: { w: 29, h: 32, ox: 11, oy: 3 } },
  { row: 10, col: 3, rowName: 'heavy_attack', label: 'r10c3', viewport: { w: 28, h: 32, ox: 11, oy: 1 } },
  { row: 10, col: 4, rowName: 'heavy_attack', label: 'r10c4', viewport: { w: 39, h: 48, ox: 22, oy: 0 } },
  { row: 10, col: 5, rowName: 'heavy_attack', label: 'r10c5', viewport: { w: 39, h: 24, ox: 22, oy: 24 } },
  { row: 10, col: 6, rowName: 'heavy_attack', label: 'r10c6', viewport: { w: 39, h: 24, ox: 22, oy: 24 } },
  { row: 11, col: 0, rowName: 'hurt', label: 'r11c0', viewport: { w: 23, h: 31, ox: 20, oy: 17 } },
  { row: 11, col: 1, rowName: 'hurt', label: 'r11c1', viewport: { w: 23, h: 29, ox: 20, oy: 18 } },
  { row: 11, col: 2, rowName: 'hurt', label: 'r11c2', viewport: { w: 23, h: 29, ox: 20, oy: 17 } },
  { row: 11, col: 3, rowName: 'hurt', label: 'r11c3', viewport: { w: 23, h: 29, ox: 20, oy: 16 } },
  { row: 12, col: 0, rowName: 'death', label: 'r12c0', viewport: { w: 23, h: 31, ox: 20, oy: 17 } },
  { row: 12, col: 1, rowName: 'death', label: 'r12c1', viewport: { w: 27, h: 29, ox: 16, oy: 18 } },
  { row: 12, col: 2, rowName: 'death', label: 'r12c2', viewport: { w: 27, h: 29, ox: 16, oy: 17 } },
  { row: 12, col: 3, rowName: 'death', label: 'r12c3', viewport: { w: 27, h: 29, ox: 16, oy: 16 } },
  { row: 12, col: 4, rowName: 'death', label: 'r12c4', viewport: { w: 25, h: 28, ox: 18, oy: 20 } },
  { row: 12, col: 5, rowName: 'death', label: 'r12c5', viewport: { w: 23, h: 27, ox: 20, oy: 21 } },
  { row: 12, col: 6, rowName: 'death', label: 'r12c6', viewport: { w: 23, h: 20, ox: 22, oy: 28 } },
  { row: 12, col: 7, rowName: 'death', label: 'r12c7', viewport: { w: 23, h: 14, ox: 22, oy: 34 } },
  { row: 12, col: 8, rowName: 'death', label: 'r12c8', viewport: { w: 22, h: 14, ox: 23, oy: 34 } },
  { row: 12, col: 9, rowName: 'death', label: 'r12c9', viewport: { w: 22, h: 13, ox: 23, oy: 35 } },
  { row: 12, col: 10, rowName: 'death', label: 'r12c10', viewport: { w: 22, h: 13, ox: 23, oy: 35 } },
  { row: 12, col: 11, rowName: 'death', label: 'r12c11', viewport: { w: 22, h: 13, ox: 23, oy: 35 } },
  { row: 12, col: 12, rowName: 'death', label: 'r12c12', viewport: { w: 22, h: 13, ox: 23, oy: 35 } },
  { row: 12, col: 13, rowName: 'death', label: 'r12c13', viewport: { w: 22, h: 13, ox: 23, oy: 35 } },
  { row: 12, col: 14, rowName: 'death', label: 'r12c14', viewport: { w: 22, h: 13, ox: 23, oy: 35 } },
];

export function getSheetFrame(row: number, col: number): SheetFrameLabel | undefined {
  return MOUSE_SHEET_FRAMES.find((f) => f.row === row && f.col === col);
}

export function getSheetRowFrames(row: number): SheetFrameLabel[] {
  return MOUSE_SHEET_FRAMES.filter((f) => f.row === row);
}
