{ pkgs }:
let
  sorttyPython = pkgs.python3.withPackages (p: [ p.art ]);
in {
  sortty = pkgs.stdenvNoCC.mkDerivation {
    pname = "sortty";
    version = "1.8-unstable-3442fb2";
    src = pkgs.fetchFromGitHub {
      owner = "qsser";
      repo = "sortty";
      rev = "3442fb28a3e7618ee0b5302b7ac55d873d069a9b";
      hash = "sha256-Vepl/XjQS3nX1hlXPCnWFcjulaAvl+c1g3jfGKq6mss=";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      mkdir -p $out/lib/sortty $out/bin
      cp src/*.py $out/lib/sortty/
      substituteInPlace $out/lib/sortty/sortty.py \
        --replace-fail 'os.system("python3 "' 'os.system("${sorttyPython}/bin/python3 "'
      makeWrapper ${sorttyPython}/bin/python3 $out/bin/sortty \
        --add-flags "$out/lib/sortty/sortty.py" \
        --set TERMINFO ${pkgs.ncurses}/share/terminfo
    '';
    meta.homepage = "https://github.com/qsser/sortty";
  };
  ascii-rain = pkgs.stdenv.mkDerivation {
    pname = "ascii-rain";
    version = "unstable-39396de";
    src = pkgs.fetchFromGitHub {
      owner = "nkleemann";
      repo = "ascii-rain";
      rev = "39396dea0a84b4580f0ee5f46de9de4468566ed0";
      hash = "sha256-v2YN5epe3ZIkjc7he9Kc62v9Oalepu7t3vGzNFRNr3M=";
    };
    buildInputs = [ pkgs.ncurses ];
    buildPhase = "$CC rain.c -o ascii-rain -lncurses";
    installPhase = ''
      install -Dm755 ascii-rain $out/bin/ascii-rain
      ln -s ascii-rain $out/bin/rain
    '';
    meta.homepage = "https://github.com/nkleemann/ascii-rain";
  };
}
