function resolveMailhogBaseUrl() {
  const configuredPort = (process.env.MAILHOG_UI_PORT || '8025').trim();

  if (configuredPort.startsWith('http://') || configuredPort.startsWith('https://')) {
    return configuredPort.replace(/\/+$/, '');
  }

  return `http://127.0.0.1:${configuredPort}`;
}

async function listMailhogMessages() {
  const response = await fetch(`${resolveMailhogBaseUrl()}/api/v2/messages`);
  if (!response.ok) {
    throw new Error(`Failed to load MailHog messages: ${response.status}`);
  }

  const payload = await response.json();
  return payload.items || [];
}

async function clearMailhogMessages() {
  const response = await fetch(`${resolveMailhogBaseUrl()}/api/v1/messages`, {
    method: 'DELETE',
  });

  if (!response.ok) {
    throw new Error(`Failed to clear MailHog messages: ${response.status}`);
  }
}

function messageRecipients(message) {
  return (message.To || []).map((recipient) => `${recipient.Mailbox}@${recipient.Domain}`.toLowerCase());
}

function messageSubject(message) {
  return message.Content?.Headers?.Subject?.[0] || '';
}

function messageBody(message) {
  return message.Content?.Body || '';
}

async function waitForMailhogMessage({ to, subjectIncludes, bodyIncludes, timeoutMs = 10000, pollMs = 250 }) {
  const recipient = to.toLowerCase();
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const messages = await listMailhogMessages();
    const matchingMessage = messages.find((message) => {
      const recipients = messageRecipients(message);
      const subject = messageSubject(message);
      const body = messageBody(message);

      return (
        recipients.includes(recipient) &&
        (!subjectIncludes || subject.includes(subjectIncludes)) &&
        (!bodyIncludes || body.includes(bodyIncludes))
      );
    });

    if (matchingMessage) {
      return matchingMessage;
    }

    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }

  throw new Error(
    `Timed out waiting for MailHog message to ${to} with subject containing "${subjectIncludes || ''}"`,
  );
}

module.exports = {
  clearMailhogMessages,
  waitForMailhogMessage,
};
