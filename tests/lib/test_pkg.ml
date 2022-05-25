open Rresult
open Dune_release
module Stdext = Dune_release.Stdext

let test_version_line_re =
  let make_test ~input ~expected =
    let test_name =
      if expected then input ^ "is a valid version field line"
      else input ^ "is not a valid version field line"
    in
    let test_fun () =
      let re = Re.compile Dune_release.Pkg.version_line_re in
      let actual = Re.execp re input in
      Alcotest.(check bool) test_name expected actual
    in
    (test_name, `Quick, test_fun)
  in
  [
    make_test ~input:"" ~expected:false;
    make_test ~input:{|version:""|} ~expected:false;
    make_test ~input:{|version:"1"|} ~expected:true;
    make_test ~input:{|version:     "1"    |} ~expected:true;
    make_test ~input:{|version:"1.jfpojef.adp921709"|} ~expected:true;
  ]

let test_prepare_opam_for_distrib =
  let make_test ~name ~version ~content ~expected () =
    let version = Version.of_string version in
    let test_name = "prepare_opam_for_distrib: " ^ name in
    let test_fun () =
      let actual =
        Dune_release.Pkg.prepare_opam_for_distrib ~version ~content
      in
      Alcotest.(check (list string)) test_name expected actual
    in
    (test_name, `Quick, test_fun)
  in
  [
    make_test ~name:"empty" ~content:[] ~version:"1"
      ~expected:[ {|version: "1"|} ] ();
    make_test ~name:"replace version" ~content:[ {|version: "1"|} ] ~version:"2"
      ~expected:[ {|version: "2"|} ] ();
    make_test ~name:"only replace version field"
      ~content:
        [
          {|version: "1"|};
          {|description: """|};
          {|version: "1" blablabla|};
          {|"""|};
        ]
      ~version:"2"
      ~expected:
        [
          {|version: "2"|};
          {|description: """|};
          {|version: "1" blablabla|};
          {|"""|};
        ]
      ();
  ]

let make_test f ?version ?tag ?keep_v ?opam ~test_name ~name expected =
  let tag = Stdext.Option.map ~f:Vcs.Tag.of_string tag in
  let version = Stdext.Option.map ~f:Version.of_string version in
  let test () =
    let expected = Ok (Fpath.v expected) in
    let actual =
      (match opam with
      | None -> Ok None
      | Some lines ->
          let file = Fpath.(v "opam-tmp") in
          let lines = ("opam-version", "1.2") :: lines in
          let lines = List.map (fun (k, v) -> Fmt.str "%s: %S" k v) lines in
          Bos.OS.File.write_lines file lines >>| fun () -> Some file)
      >>= fun opam ->
      let p = Pkg.v ~dry_run:false ~name ?tag ?version ?keep_v ?opam () in
      f p
    in
    Alcotest.(check Alcotest_ext.(result_msg path)) test_name expected actual
  in
  (test_name, `Quick, test)

let distrib_uri =
  let make_test ~test_name =
    let test_name = "distrib_uri:" ^ test_name in
    make_test ~test_name ~name:"yo" (fun x ->
        Pkg.infer_github_distrib_uri x >>| Fpath.v)
  in
  let dev_repo = [ ("dev-repo", "git@github.com:foo/bar.git") ] in
  let homepage = [ ("homepage", "https://github.com/foo/bar") ] in
  let url = "https://github.com/foo/bar/releases/download/v0/yo-v0.tbz" in
  [
    make_test ~test_name:"1" ~opam:dev_repo ~tag:"v0" url;
    make_test ~test_name:"2" ~opam:homepage ~tag:"v0" url;
    make_test ~test_name:"3" ~opam:dev_repo ~version:"v0" url;
    make_test ~test_name:"4" ~opam:homepage ~version:"v0" url;
    make_test ~test_name:"5" ~opam:dev_repo ~tag:"v0" ~keep_v:false url;
    make_test ~test_name:"6" ~opam:homepage ~tag:"v0" ~keep_v:true url;
    make_test ~test_name:"7" ~opam:dev_repo ~tag:"v0" ~version:"x" url;
    make_test ~test_name:"8" ~opam:homepage ~tag:"v0" ~version:"x" url;
    make_test ~test_name:"9"
      ~opam:[ ("homepage", "https://foo.github.io/bar") ]
      ~tag:"v0" url;
  ]

let test_dune_project_name =
  let test ~name lines ~expected =
    ( name,
      `Quick,
      fun () ->
        let got = Pkg.dune_project_name_string lines in
        Alcotest.check Alcotest.(option string) __LOC__ expected got )
  in
  [
    test ~name:"ok" [ "(lang dune 2.4)"; "(name xyz)" ] ~expected:(Some "xyz");
    test ~name:"no name" [ "(lang dune 2.4)" ] ~expected:None;
    test ~name:"opam file generation"
      [
        "(lang dune 2.7)";
        "(name first)";
        "(generate_opam_files true)";
        "(package";
        " (name first))";
        "(package";
        " (name second))";
      ]
      ~expected:(Some "second");
  ]

let suite =
  ( "Pkg",
    List.concat
      [
        test_version_line_re;
        test_prepare_opam_for_distrib;
        distrib_uri;
        test_dune_project_name;
      ] )
