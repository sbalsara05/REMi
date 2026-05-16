function buildSystemPrompt({ captureMode, appName, hoveredText, selectionRect, cursorX, cursorY }) {
  const parts = [
    'You are REMi Magic Pointer, a macOS assistant that answers questions about what the user is looking at on screen.',
    `Capture mode: ${captureMode === 'selection' ? 'region selection' : 'cursor context'}.`,
  ];

  if (appName) {
    parts.push(`Foreground app: ${appName}.`);
  }
  if (hoveredText) {
    parts.push(`Text near cursor: ${hoveredText.slice(0, 2000)}`);
  }
  if (selectionRect) {
    parts.push(
      `Selection rect (screen coords): x=${selectionRect.x}, y=${selectionRect.y}, width=${selectionRect.width}, height=${selectionRect.height}.`,
    );
  } else {
    parts.push(`Cursor position: x=${cursorX}, y=${cursorY}.`);
  }

  parts.push('Use the screenshot when provided. Be concise and actionable.');
  return parts.join('\n');
}

function buildUserContent({ query, screenshotBase64 }) {
  const content = [{ type: 'text', text: query }];

  if (screenshotBase64) {
    const raw = screenshotBase64.replace(/^data:image\/\w+;base64,/, '');
    content.push({
      type: 'image_url',
      image_url: {
        url: `data:image/png;base64,${raw}`,
        detail: 'auto',
      },
    });
  }

  return content;
}

function buildMessages(payload) {
  const {
    query,
    captureMode,
    appName,
    hoveredText,
    selectionRect,
    cursorX,
    cursorY,
    screenshotBase64,
  } = payload;

  return [
    {
      role: 'system',
      content: buildSystemPrompt({
        captureMode,
        appName,
        hoveredText,
        selectionRect,
        cursorX,
        cursorY,
      }),
    },
    {
      role: 'user',
      content: buildUserContent({ query, screenshotBase64 }),
    },
  ];
}

module.exports = {
  buildSystemPrompt,
  buildUserContent,
  buildMessages,
};
