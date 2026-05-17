function buildSystemPrompt({
  captureMode,
  appName,
  hoveredText,
  selectionRect,
  cursorX,
  cursorY,
  mergedContextText,
  screenshotCount,
  ragContext,
  manualSkills,
}) {
  const parts = [];

  parts.push(`You are REMi, an intelligent screen-aware assistant embedded in the user's desktop.`);
  parts.push(`You can see what the user is looking at and answer questions about it directly.`);
  parts.push(`Be concise. Respond in 1-3 sentences unless the user asks for detail.`);
  parts.push(``);

  if (captureMode === 'selection' && selectionRect) {
    parts.push(`The user drew a selection rectangle on their screen (x:${Math.round(selectionRect.x)}, y:${Math.round(selectionRect.y)}, ${Math.round(selectionRect.width)}x${Math.round(selectionRect.height)}px).`);
    parts.push(`A screenshot of the selected region is attached.`);
  } else {
    parts.push(`The user wiggled their cursor at position (${Math.round(cursorX)}, ${Math.round(cursorY)}) to ask about what's under it.`);
    parts.push(`A screenshot of the region around the cursor is attached.`);
  }

  if (appName) {
    parts.push(`Active application: ${appName}.`);
  }

  if (hoveredText && hoveredText.trim().length > 0) {
    const truncated = hoveredText.trim().slice(0, 500);
    parts.push(`Text extracted from the UI element under the cursor: "${truncated}"`);
    parts.push(`Use this text as primary context - it is more reliable than the screenshot for text content.`);
  }

  if (mergedContextText) {
    parts.push(`The user captured ${screenshotCount || 0} context point(s) before asking:`);
    parts.push(mergedContextText);
  }

  if (ragContext && ragContext.trim().length > 0) {
    parts.push(``);
    parts.push(`Relevant context from the user's prior REMi sessions (use as background knowledge):`);
    parts.push(ragContext.trim());
    parts.push(`Do not mention that you retrieved this from a database.`);
  }

  if (Array.isArray(manualSkills) && manualSkills.length > 0) {
    parts.push(``);
    parts.push(`The user invoked skills for this turn: ${manualSkills.join(', ')}.`);
  }

  parts.push(``);
  parts.push(`Answer the user's question about what they are looking at.`);

  return parts.join('\n');
}

function buildUserContent({ query, screenshotBase64, additionalScreenshotsBase64 }) {
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

  if (Array.isArray(additionalScreenshotsBase64)) {
    for (const screenshot of additionalScreenshotsBase64) {
      if (!screenshot) {
        continue;
      }
      const raw = screenshot.replace(/^data:image\/\w+;base64,/, '');
      content.push({
        type: 'image_url',
        image_url: {
          url: `data:image/png;base64,${raw}`,
          detail: 'auto',
        },
      });
    }
  }

  return content;
}

function buildMessages(payload) {
  const {
    query,
    systemPrompt,
    captureMode,
    appName,
    hoveredText,
    selectionRect,
    cursorX,
    cursorY,
    screenshotBase64,
    additionalScreenshotsBase64,
    mergedContextText,
    screenshotCount,
  } = payload;

  return [
    {
      role: 'system',
      content:
        systemPrompt ||
        buildSystemPrompt({
          captureMode,
          appName,
          hoveredText,
          selectionRect,
          cursorX,
          cursorY,
          mergedContextText,
          screenshotCount,
        }),
    },
    {
      role: 'user',
      content: buildUserContent({ query, screenshotBase64, additionalScreenshotsBase64 }),
    },
  ];
}

module.exports = {
  buildSystemPrompt,
  buildUserContent,
  buildMessages,
};
