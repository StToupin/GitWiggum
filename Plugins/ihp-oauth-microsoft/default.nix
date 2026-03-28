{ mkDerivation, aeson, base, bytestring, hasql-implicits, ihp, lens, lib, text, transformers
, typerep-map, uri-encode, wreq
}:
mkDerivation {
  pname = "ihp-oauth-microsoft";
  version = "0.0.1";
  src = ./.;
  libraryHaskellDepends = [
    aeson base bytestring hasql-implicits ihp lens text transformers typerep-map uri-encode wreq
  ];
  description = "Login with Microsoft Entra ID using OpenID Connect";
  license = lib.licenses.mit;
}
