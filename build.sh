#!/bin/bash -e -x

################################################################################

if hash xbuild &> /dev/null ; then
  export BUILD=xbuild
  export RUN=mono
elif hash msbuild.exe &> /dev/null ; then
  export BUILD=msbuild.exe
  export RUN=
else
  echo "Couldn't find build command."
  exit 1
fi

################################################################################

equals() {
  if [ -f "$1" -a -f "$2" ] ; then
    diff -q "$1" "$2" > /dev/null
  else
    return 1
  fi
}

overwrite-changed() {
  cat > .tmp
  if ! equals .tmp "$1" ; then
    cp .tmp "$1"
  fi
  rm .tmp
}

check-clean() {
  local BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [ "master" != "$BRANCH" ] ; then
    echo "Have you merged your changes to master? (currently on $BRANCH)"
    exit 1
  fi

  local CHANGES="$(git status --porcelain)"
  if [ "" != "$CHANGES" ] ; then
    echo "Have you committed all local changes?

Changes:
$CHANGES"
    exit 1
  fi

  local BEHIND="$(git rev-list --count @{upstream}..HEAD)"
  if [ "0" != "$BEHIND" ] ; then
    echo "Have you pushed everything to upstream? ($BEHIND commits behind upstream)"
    exit 1
  fi
}

run-paket() {
  local PAKET=.paket/paket.exe

  if [ ! -f $PAKET ] ; then
    $RUN .paket/paket.bootstrapper.exe
    chmod +x $PAKET
  fi

  $RUN $PAKET "$@"
}

################################################################################

export PROJECT_URL="https://github.com/Hopac/Hopac"
export SUMMARY="A library for Higher-Order, Parallel, Asynchronous and Concurrent programming in F#."
export DESCRIPTION="Inspired by languages like Concurrent ML and Cilk, Hopac is a library for F# with the aim of making it easier to write efficient parallel, asynchronous, concurrent and reactive programs. Hopac is licensed under a MIT-style license. See project website for further information."
export COMPANY="Housemarque Inc."
export COPYRIGHT="© $COMPANY"
export TAGS="f#, fsharp, parallel, async, concurrent, reactive"
export LICENSE_URL="$PROJECT_URL/blob/master/LICENSE.md"
export ICON_URL="https://avatars2.githubusercontent.com/u/10173903"

################################################################################

export VERSION="$(cat RELEASE_NOTES.md                |
                  grep -e '^#### '                    |
                  sed -e 's/^#### *\([^ ]*\) .*/\1/g' |
                  head -n 1)"

N="$(cat RELEASE_NOTES.md           |
     grep -n -e '^ *$'              |
     sed -e 's#^\([0-9]*\).*$#\1#g' |
     head -n 1)"

export NOTES="$(cat RELEASE_NOTES.md         |
                head -n $((N-1))             |
                sed -e 's#^\(.*\)$#    \1#g' |
                tail -n $((N-2)))"

################################################################################

clean() {
  find Libs -name bin | xargs rm -rf
  find Libs -name obj | xargs rm -rf

  rm -rf .gh-pages
  rm -rf .nuget
  rm -rf .paket/paket.exe
  rm -rf packages
}

get-deps() {
  run-paket install
}

generate-infos() {
  for LIB in Hopac Hopac.Platform.Net ; do
    overwrite-changed Libs/$LIB/AssemblyInfo.fs <<EOF
// NOTE: This is a generated file.

namespace System

open System.Reflection

[<assembly: AssemblyTitleAttribute("$LIB")>]
[<assembly: AssemblyProductAttribute("$LIB")>]
[<assembly: AssemblyDescriptionAttribute("$SUMMARY")>]
[<assembly: AssemblyVersionAttribute("$VERSION")>]
[<assembly: AssemblyFileVersionAttribute("$VERSION")>]
[<assembly: AssemblyCompanyAttribute("$COMPANY")>]
[<assembly: AssemblyCopyrightAttribute("$COPYRIGHT")>]

do ()
EOF
  done
  
  for LIB in Hopac.Core ; do
    overwrite-changed Libs/$LIB/AssemblyInfo.cs <<EOF
// NOTE: This is a generated file.

using System.Reflection;

[assembly: AssemblyTitleAttribute("$LIB")]
[assembly: AssemblyProductAttribute("$LIB")]
[assembly: AssemblyDescriptionAttribute("$SUMMARY")]
[assembly: AssemblyVersionAttribute("$VERSION")]
[assembly: AssemblyFileVersionAttribute("$VERSION")]
[assembly: AssemblyCompanyAttribute("$COMPANY")]
[assembly: AssemblyCopyrightAttribute("$COPYRIGHT")]
EOF
  done
}

build-sln() {
  for SOLUTION in Hopac.sln ; do
    for CONFIG in Debug Release ; do
      $BUILD /nologo /verbosity:quiet /p:Configuration=$CONFIG $SOLUTION
    done
  done
}

build-nupkg() {
  mkdir -p .nuget

  local TEMPLATE=.nuget/Hopac.template

  overwrite-changed $TEMPLATE <<EOF
type file
id Hopac
version $VERSION
summary $SUMMARY
description $DESCRIPTION
copyright Copyright 2015
authors $COMPANY
owners $COMPANY
tags $TAGS
projectUrl $PROJECT_URL
iconUrl $ICON_URL
licenseUrl $LICENSE_URL
releaseNotes
$NOTES
files
    ../Libs/Hopac.Core/bin/Release/Hopac.Core.dll ==> lib/net45
    ../Libs/Hopac.Core/bin/Release/Hopac.Core.xml ==> lib/net45
    ../Libs/Hopac/bin/Release/Hopac.dll ==> lib/net45
    ../Libs/Hopac/bin/Release/Hopac.xml ==> lib/net45
    ../Libs/Hopac.Platform.Net/bin/Release/Hopac.Platform.dll ==> lib/net45
dependencies FSharp.Core >= 3.1.2.5
EOF

  run-paket pack output .nuget templatefile $TEMPLATE
}

generate-docs() {
  if [ ! -d .gh-pages ] ; then
    git clone -b gh-pages $PROJECT_URL .gh-pages
  fi

  ./FsiRefGen/run --out .gh-pages/$VERSION --name Hopac -- \
      Libs/Hopac/Hopac.fsi                        \
      Libs/Hopac/Stream.fsi                       \
      Libs/Hopac/TopLevel.fsi
}

build() {
  get-deps
  generate-infos
  build-sln
  generate-docs
  build-nupkg
}

run-tests() {
  for CONFIG in Debug Release ; do
    for TEST in $(ls Tests) ; do
      echo "$TEST ($CONFIG)"
      $RUN "Tests/$TEST/bin/$CONFIG/$TEST.exe"
      echo
    done
  done
}

publish-docs() {
  pushd .gh-pages
  git add $VERSION
  git commit -m "Updated docs for $VERSION"
  git push
  popd
}

publish-nupkg() {
  paket push url https://www.nuget.org file .nuget/Hopac.$VERSION.nupkg
  git tag -a $VERSION -m $VERSION
  git push --follow-tags
}

publish() {
  cat <<EOF

You are about to publish Hopac.

Version: $VERSION

Release notes:
$NOTES

EOF

  check-clean

  publish-nupkg
  publish-docs
}

################################################################################

case "$1" in
  "clean")
    clean
    ;;
  "build")
    build
    ;;
  "test")
    build
    run-tests
    ;;
  "publish")
    clean
    build
    run-tests
    publish
    ;;
  *)
    echo "Unknown command '$command'."
    exit 1
    ;;
esac
