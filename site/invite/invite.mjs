// Fragment-only input: never read query strings, transmit invitations, or redeem here.
export function parseInviteCode(hash) {
  if (typeof hash !== 'string') return null;
  return /^#invite_code=([a-f0-9]{48})$/.exec(hash)?.[1] ?? null;
}
export function appInviteUrl(code) {
  if (!/^[a-f0-9]{48}$/.test(code ?? '')) return null;
  return `com.kang88.carcar://invite?invite_code=${code}`;
}
export function mountInvite({ document, location, clipboard }) {
  const open = document.getElementById('open-app');
  const copy = document.getElementById('copy-code');
  const field = document.getElementById('invite-code');
  const area = document.getElementById('code-area');
  const status = document.getElementById('status');
  const code = parseInviteCode(location.hash);
  if (!code) {
    status.textContent = '초대 링크를 확인할 수 없어요. 가족에게 링크를 다시 받아 주세요.';
    return;
  }
  field.value = code;
  area.hidden = false;
  open.disabled = false;
  copy.disabled = false;
  status.textContent = '앱에서 열거나 코드를 복사해 주세요. 초대 사용 여부는 앱에서 확인해요.';
  open.addEventListener('click', () => {
    status.textContent = '앱이 열리지 않으면 코드를 복사해 두었다가 설치 후 입력해 주세요.';
    location.assign(appInviteUrl(code));
  });
  copy.addEventListener('click', async () => {
    try {
      if (!clipboard?.writeText) throw new Error('Clipboard unavailable');
      await clipboard.writeText(code);
      status.textContent = '초대 코드를 복사했어요. 차곡 앱에서 입력해 주세요.';
    } catch {
      field.focus();
      field.select();
      status.textContent = '자동 복사가 안 돼요. 선택된 코드를 직접 복사해 주세요.';
    }
  });
}
if (typeof window !== 'undefined') {
  mountInvite({ document: window.document, location: window.location, clipboard: window.navigator.clipboard });
}
