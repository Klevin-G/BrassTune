import { googleSignInLogo } from '../assets/googleSignInLogo';

/** Official Google Identity artwork. The parent button provides the accessible label. */
export function GoogleIcon({ size = 18 }: { size?: number }) {
  return (
    <img
      src={googleSignInLogo}
      width={size}
      height={size}
      alt=""
      aria-hidden="true"
      draggable={false}
    />
  );
}
