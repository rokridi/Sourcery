import Quick
import Nimble
import PathKit
#if SWIFT_PACKAGE
import Foundation
@testable import SourceryLib
#else
@testable import Sourcery
#endif
#if !canImport(ObjectiveC)
import CDispatch
#endif
@testable import SourceryRuntime
import XcodeProj

private let version = "Major.Minor.Patch"

// swiftlint:disable file_length type_body_length
class SourcerySpecTests: QuickSpec {
    // swiftlint:disable:next function_body_length
    override func spec() {
        func update(code: String, in path: Path) { guard (try? path.write(code)) != nil else { fatalError() } }

        describe("Sourcery") {
            var outputDir = Path("/tmp")
            var output: Output { return Output(outputDir) }

            beforeEach {
                outputDir = Stubs.cleanTemporarySourceryDir()
            }

            context("with already generated files") {
                let templatePath = Stubs.templateDirectory + Path("Other.stencil")
                let sourcePath = outputDir + Path("Source.swift")
                var generatedFileModificationDate: Date!
                var newGeneratedFileModificationDate: Date!

                func fileModificationDate(url: URL) -> Date? {
                    guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                        return nil
                    }
                    return attr[FileAttributeKey.modificationDate] as? Date
                }

                beforeEach {
                    update(code: """
                        class Foo {
                        }
                        """, in: sourcePath)

                    _ = try? Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(
                        .sources(Paths(include: [sourcePath])),
                        usingTemplates: Paths(include: [templatePath]),
                        output: output,
                        baseIndentation: 0
                    )
                }

                context("without changes") {
                    it("doesn't update existing files") {
                        let generatedFilePath = outputDir + Sourcery().generatedPath(for: templatePath)
                        generatedFileModificationDate = fileModificationDate(url: generatedFilePath.url)
                        DispatchQueue.main.asyncAfter( deadline: DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) {
                            _ = try? Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0)
                            newGeneratedFileModificationDate = fileModificationDate(url: generatedFilePath.url)
                        }
                        expect(newGeneratedFileModificationDate).toEventually(equal(generatedFileModificationDate))
                    }
                }

                context("with changes") {
                    let anotherSourcePath = outputDir + Path("AnotherSource.swift")

                    beforeEach {
                        update(code: """
                            class Bar {
                            }
                            """, in: anotherSourcePath)
                    }

                    it("updates existing files") {
                        let generatedFilePath = outputDir + Sourcery().generatedPath(for: templatePath)
                        generatedFileModificationDate = fileModificationDate(url: generatedFilePath.url)
                        DispatchQueue.main.asyncAfter( deadline: DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) {
                            _ = try? Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath, anotherSourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0)
                            newGeneratedFileModificationDate = fileModificationDate(url: generatedFilePath.url)
                        }
                        expect(newGeneratedFileModificationDate).toNotEventually(equal(generatedFileModificationDate))
                    }
                }
            }

            context("given a single template") {
                let templatePath = Stubs.templateDirectory + Path("Basic.stencil")
                let expectedResult = try? (Stubs.resultDirectory + Path("Basic.swift")).read(.utf8).withoutWhitespaces

                describe("using inline generation") {
                    let templatePath = outputDir + Path("FakeTemplate.stencil")
                    let sourcePath = outputDir + Path("Source.swift")

                    beforeEach {
                        update(code: """
                            class Foo {
                            // sourcery:inline:Foo.Inlined

                            // This will be replaced
                            Last line
                            // sourcery:end
                            }
                            """, in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:Foo.Inlined
                            var property = 2
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())
                    }

                    it("replaces placeholder with generated code") {
                        let expectedResult = """
                            class Foo {
                            // sourcery:inline:Foo.Inlined
                            var property = 2
                            // Line Three
                            // sourcery:end
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("removes code from within generated template") {
                        let expectedResult = """
                            // Generated using Sourcery Major.Minor.Patch — https://github.com/krzysztofzablocki/Sourcery
                            // DO NOT EDIT

                            // Line One
                            """

                        let generatedPath = outputDir + Sourcery().generatedPath(for: templatePath)

                        let result = try? generatedPath.read(.utf8)
                        expect(result?.withoutWhitespaces).to(equal(expectedResult.withoutWhitespaces))
                    }

                    it("does not remove code from within generated template when missing origin") {
                        update(code: """
                            class Foo {
                            // sourcery:inline:Bar.Inlined

                            // This will be replaced
                            Last line
                            // sourcery:end
                            }
                            """, in: sourcePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            // Generated using Sourcery Major.Minor.Patch — https://github.com/krzysztofzablocki/Sourcery
                            // DO NOT EDIT

                            // Line One
                            // sourcery:inline:Foo.Inlined
                            var property = 2
                            // Line Three
                            // sourcery:end
                            """

                        let generatedPath = outputDir + Sourcery().generatedPath(for: templatePath)

                        let result = try? generatedPath.read(.utf8)
                        expect(result?.withoutWhitespaces).to(equal(expectedResult.withoutWhitespaces))
                    }

                    it("does not create generated file with empty content") {
                        update(code: """
                            // sourcery:inline:Foo.Inlined
                            var property = 2
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true, prune: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let generatedPath = outputDir + Sourcery().generatedPath(for: templatePath)

                        let result = try? generatedPath.read(.utf8)
                        expect(result).to(beNil())
                    }

                    it("inline multiple generated code blocks correctly") {
                        update(code: """
                            class Foo {
                            // sourcery:inline:Foo.Inlined

                            // This will be replaced
                            Last line
                            // sourcery:end
                            }

                            class Bar {
                            // sourcery:inline:Bar.Inlined

                            // This will be replaced
                            Last line
                            // sourcery:end
                            }
                            """, in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:Bar.Inlined
                            var property = bar
                            // Line Three
                            // sourcery:end
                            // Line One
                            // sourcery:inline:Foo.Inlined
                            var property = foo
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {
                            // sourcery:inline:Foo.Inlined
                            var property = foo
                            // Line Three
                            // sourcery:end
                            }

                            class Bar {
                            // sourcery:inline:Bar.Inlined
                            var property = bar
                            // Line Three
                            // sourcery:end
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("indents generated code blocks correctly") {
                        update(code: """
                            class Foo {
                                // sourcery:inline:Foo.Inlined

                                // This will be replaced
                                Last line
                                // sourcery:end

                                class Bar {
                                    // sourcery:inline:Bar.Inlined

                                    // This will be replaced
                                    Last line
                                    // sourcery:end
                                }
                            }
                            """, in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:Bar.Inlined
                            var property = bar

                            // Line Three
                            // sourcery:end
                            // Line One
                            // sourcery:inline:Foo.Inlined
                            var property = foo
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {
                                // sourcery:inline:Foo.Inlined
                                var property = foo
                                // Line Three
                                // sourcery:end

                                class Bar {
                                    // sourcery:inline:Bar.Inlined
                                    var property = bar

                                    // Line Three
                                    // sourcery:end
                                }
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }
                }

                describe("using automatic inline generation") {
                    let templatePath = outputDir + Path("FakeTemplate.stencil")
                    let sourcePath = outputDir + Path("Source.swift")

                    it("insert generated code in the end of type body") {
                        update(code: "class Foo {}", in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:auto:Foo.Inlined
                            var property = 2
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {
                            // sourcery:inline:auto:Foo.Inlined
                            var property = 2
                            // Line Three
                            // sourcery:end
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("insert generated code in the end of type body maintaining identation, accomodates for baseIdent") {
                        update(code:
                        """
                        class Foo {
                            struct Inner {
                            }
                        }
                        """,
                        in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:auto:Foo.Inner.Inlined
                                var property = 3
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 4) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {
                                struct Inner {

                                    // sourcery:inline:auto:Foo.Inner.Inlined
                                        var property = 3
                                    // Line Three
                                    // sourcery:end
                                }
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("insert generated code after the end of type body when using after-auto") {
                        update(code: "class Foo {}\nstruct Boo {}", in: sourcePath)

                        update(code: """
                            // sourcery:inline:after-auto:Foo.Inlined
                            var property = 2
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {}
                            // sourcery:inline:after-auto:Foo.Inlined
                            var property = 2
                            // sourcery:end
                            struct Boo {}
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("insert generated code line before the end of type body") {
                        update(code: """
                        class Foo {
                            var property = 1 }
                        """, in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:auto:Foo.Inlined
                            var property = 2
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {

                                // sourcery:inline:auto:Foo.Inlined
                                var property = 2
                                // Line Three
                                // sourcery:end
                                var property = 1 }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("handles UTF16 characters") {
                        update(code: """
                            class A {
                                let 👩‍🚀: String
                            }
                            """, in: sourcePath)
                        update(code: """
                            {% for type in types.all %}
                            // sourcery:inline:auto:{{ type.name }}.init
                            init({% for variable in type.storedVariables %}{{variable.name}}: {{variable.typeName}}{% ifnot forloop.last %}, {% endif %}{% endfor %}) {
                            {% for variable in type.storedVariables %}
                                self.{{variable.name}} = {{variable.name}}
                            {% endfor %}
                            }
                            // sourcery:end
                            {% endfor %}
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class A {
                                let 👩‍🚀: String

                            // sourcery:inline:auto:A.init
                            init(👩‍🚀: String) {
                                self.👩‍🚀 = 👩‍🚀
                            }
                            // sourcery:end
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("handles previously generated code with UTF16 characters") {
                        update(code: """
                            class A {
                                let 👩‍🚀: String

                                // sourcery:inline:auto:A.init
                                init(👩‍🚀: String) {
                                    self.👩‍🚀 = 👩‍🚀
                                }
                                // sourcery:end
                            }

                            class B {
                                let 👩‍🚀: String
                            }
                            """, in: sourcePath)
                        update(code: """
                            {% for type in types.all %}
                            // sourcery:inline:auto:{{ type.name }}.init
                            init({% for variable in type.storedVariables %}{{variable.name}}: {{variable.typeName}}{% ifnot forloop.last %}, {% endif %}{% endfor %}) {
                            {% for variable in type.storedVariables %}
                                self.{{variable.name}} = {{variable.name}}
                            {% endfor %}
                            }
                            // sourcery:end
                            {% endfor %}
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class A {
                                let 👩‍🚀: String

                                // sourcery:inline:auto:A.init
                                init(👩‍🚀: String) {
                                    self.👩‍🚀 = 👩‍🚀
                                }
                                // sourcery:end
                            }

                            class B {
                                let 👩‍🚀: String

                            // sourcery:inline:auto:B.init
                            init(👩‍🚀: String) {
                                self.👩‍🚀 = 👩‍🚀
                            }
                            // sourcery:end
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("insert generated code in multiple types") {
                        update(code: """
                            class Foo {}

                            class Bar {}
                            """, in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:auto:Bar.Inlined
                            var property = bar
                            // Line Three
                            // sourcery:end

                            // Line One
                            // sourcery:inline:auto:Foo.Inlined
                            var property = foo
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {
                            // sourcery:inline:auto:Foo.Inlined
                            var property = foo
                            // Line Three
                            // sourcery:end
                            }

                            class Bar {
                            // sourcery:inline:auto:Bar.Inlined
                            var property = bar
                            // Line Three
                            // sourcery:end
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("insert same generated code in multiple types") {
                        update(code: """
                            class Foo {
                            // sourcery:inline:auto:Foo.fake
                            // sourcery:end
                            }

                            class Bar {}
                            """, in: sourcePath)

                        update(code: """
                            // Line One
                            {% for type in types.all %}
                            // sourcery:inline:auto:{{ type.name }}.fake
                            var property = bar
                            // Line Three
                            // sourcery:end
                            {% endfor %}
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {
                            // sourcery:inline:auto:Foo.fake
                            var property = bar
                            // Line Three
                            // sourcery:end
                            }

                            class Bar {
                            // sourcery:inline:auto:Bar.fake
                            var property = bar
                            // Line Three
                            // sourcery:end
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("insert generated code in a nested type") {
                        update(code: """
                            class Foo {
                                class Bar {}
                            }
                            """, in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:auto:Foo.Bar.AutoInlined
                            var property = bar
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {
                                class Bar {
                            // sourcery:inline:auto:Foo.Bar.AutoInlined
                            var property = bar
                            // Line Three
                            // sourcery:end
                            }
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("insert generated code in a nested type with extension") {
                        update(code: """
                            class Foo {}

                            extension Foo {
                                class Bar {}
                            }
                            """, in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:auto:Foo.Bar.AutoInlined
                            var property = bar
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {}

                            extension Foo {
                                class Bar {
                            // sourcery:inline:auto:Foo.Bar.AutoInlined
                            var property = bar
                            // Line Three
                            // sourcery:end
                            }
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("insert generated code in both type and its nested type") {
                        update(code: """
                            class Foo {}

                            extension Foo {
                                class Bar {}
                            }
                            """, in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:auto:Foo.AutoInlined
                            var property = foo
                            // Line Three
                            // sourcery:end
                            // sourcery:inline:auto:Foo.Bar.AutoInlined
                            var property = bar
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let expectedResult = """
                            class Foo {
                            // sourcery:inline:auto:Foo.AutoInlined
                            var property = foo
                            // Line Three
                            // sourcery:end
                            }

                            extension Foo {
                                class Bar {
                            // sourcery:inline:auto:Foo.Bar.AutoInlined
                            var property = bar
                            // Line Three
                            // sourcery:end
                            }
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("inserts generated code from different templates (both inline:auto)") {
                        update(code: "class Foo {}", in: sourcePath)

                        update(code: """
                            // Line One
                            // sourcery:inline:auto:Foo.fake
                            var property = 2
                            // Line Three
                            // sourcery:end
                            """, in: templatePath)

                        let secondTemplatePath = outputDir + Path("OtherFakeTemplate.stencil")

                        update(code: """
                            // sourcery:inline:auto:Foo.otherFake
                            // Line Four
                            // sourcery:end
                            """, in: secondTemplatePath)

                        expect {
                            try Sourcery(watcherEnabled: false, cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [sourcePath])),
                                              usingTemplates: Paths(include: [secondTemplatePath, templatePath]),
                                              output: output, baseIndentation: 0)
                            }.toNot(throwError())

                        let expectedResult = """
                            class Foo {
                            // sourcery:inline:auto:Foo.fake
                            var property = 2
                            // Line Three
                            // sourcery:end

                            // sourcery:inline:auto:Foo.otherFake
                            // Line Four
                            // sourcery:end
                            }
                            """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))

                        // when regenerated
                        expect {
                            try Sourcery(watcherEnabled: false, cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [sourcePath])),
                                              usingTemplates: Paths(include: [secondTemplatePath, templatePath]),
                                              output: output, baseIndentation: 0)
                            }.toNot(throwError())

                        let newResult = try? sourcePath.read(.utf8)
                        expect(newResult).to(equal(expectedResult))
                    }

                    it("inserts generated code from different templates (both inline)") {
                        let templatePathA = outputDir + Path("InlineTemplateA.stencil")
                        let templatePathB = outputDir + Path("InlineTemplateB.stencil")
                        let sourcePath = outputDir + Path("ClassWithMultipleInlineAnnotations.swift")

                        update(code: """
                                     class ClassWithMultipleInlineAnnotations {
                                     // sourcery:inline:ClassWithMultipleInlineAnnotations.A
                                     var a0: Int
                                     // sourcery:end

                                     // sourcery:inline:ClassWithMultipleInlineAnnotations.B
                                     var b0: String
                                     // sourcery:end
                                     }
                                     """, in: sourcePath)

                        update(code: """
                                     {% for type in types.all %}
                                     // sourcery:inline:{{ type.name }}.A
                                     var a0: Int
                                     var a1: Int
                                     var a2: Int
                                     // sourcery:end
                                     {% endfor %}
                                     """, in: templatePathA)

                        update(code: """
                                     {% for type in types.all %}
                                     // sourcery:inline:{{ type.name }}.B
                                     var b0: Int
                                     var b1: Int
                                     var b2: Int
                                     // sourcery:end
                                     {% endfor %}
                                     """, in: templatePathB)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true)
                            .processFiles(.sources(Paths(include: [sourcePath])),
                                usingTemplates: Paths(include: [templatePathA, templatePathB]),
                                output: output, baseIndentation: 0)
                        }.toNot(throwError())

                        let expectedResult = """
                                             class ClassWithMultipleInlineAnnotations {
                                             // sourcery:inline:ClassWithMultipleInlineAnnotations.A
                                             var a0: Int
                                             var a1: Int
                                             var a2: Int
                                             // sourcery:end

                                             // sourcery:inline:ClassWithMultipleInlineAnnotations.B
                                             var b0: Int
                                             var b1: Int
                                             var b2: Int
                                             // sourcery:end
                                             }
                                             """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("inserts generated code from different templates (inline and inline:auto)") {
                        let templatePathA = outputDir + Path("InlineTemplateA.stencil")
                        let templatePathB = outputDir + Path("InlineTemplateB.stencil")
                        let sourcePath = outputDir + Path("ClassWithMultipleInlineAnnotations.swift")

                        /*
                         inline:auto annotations are inserted at the beginning of the last line of a declaration,
                         OR at the beginning of the last line of the containing file,
                         if proposed location out of bounds, which should not be.

                         To differentiate such cases the last line of a declaration
                         shall not be the last line of the file.
                         */

                        update(code: """
                                     class ClassWithMultipleInlineAnnotations {
                                     // sourcery:inline:ClassWithMultipleInlineAnnotations.A
                                     var a0: Int
                                     // sourcery:end
                                     }
                                     // the last line of the file
                                     """, in: sourcePath)

                        update(code: """
                                     {% for type in types.all %}
                                     // sourcery:inline:{{ type.name }}.A
                                     var a0: Int
                                     var a1: Int
                                     var a2: Int
                                     // sourcery:end
                                     {% endfor %}
                                     """, in: templatePathA)

                        update(code: """
                                     {% for type in types.all %}
                                     // sourcery:inline:auto:{{ type.name }}.B
                                     var b0: Int
                                     var b1: Int
                                     var b2: Int
                                     // sourcery:end
                                     {% endfor %}
                                     """, in: templatePathB)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true)
                            .processFiles(.sources(Paths(include: [sourcePath])),
                                usingTemplates: Paths(include: [templatePathA, templatePathB]),
                                output: output, baseIndentation: 0)
                        }.toNot(throwError())

                        let expectedResult = """
                                             class ClassWithMultipleInlineAnnotations {
                                             // sourcery:inline:ClassWithMultipleInlineAnnotations.A
                                             var a0: Int
                                             var a1: Int
                                             var a2: Int
                                             // sourcery:end

                                             // sourcery:inline:auto:ClassWithMultipleInlineAnnotations.B
                                             var b0: Int
                                             var b1: Int
                                             var b2: Int
                                             // sourcery:end
                                             }
                                             // the last line of the file
                                             """

                        let result = try? sourcePath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    context("with cache of already inserted code") {
                        beforeEach {
                            Sourcery.removeCache(for: [sourcePath])

                            update(code: "class Foo {}", in: sourcePath)

                            update(code: """
                                // Line One
                                // sourcery:inline:auto:Foo.Inlined
                                var property = 2
                                // Line Three
                                // sourcery:end
                                """, in: templatePath)

                            _ = try? Sourcery(watcherEnabled: false, cacheDisabled: false).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: Output(outputDir, linkTo: nil), baseIndentation: 0)
                        }

                        it("inserts the generated code if it was deleted") {
                            update(code: "class Foo {}", in: sourcePath)

                            expect { try Sourcery(watcherEnabled: false, cacheDisabled: false).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: Output(outputDir, linkTo: nil), baseIndentation: 0) }.toNot(throwError())

                            let expectedResult = """
                                class Foo {
                                // sourcery:inline:auto:Foo.Inlined
                                var property = 2
                                // Line Three
                                // sourcery:end
                                }
                                """

                            let result = try? sourcePath.read(.utf8)
                            expect(result).to(equal(expectedResult))
                        }

                        afterEach {
                            Sourcery.removeCache(for: [sourcePath])
                        }
                    }
                }

                describe("using per file generation") {
                    let templatePath = outputDir + Path("FakeTemplate.stencil")
                    let sourcePath = outputDir + Path("Source.swift")

                    beforeEach {
                        update(code: "class Foo { }", in: sourcePath)

                        update(code: """
                            // Line One
                            {% for type in types.all %}
                            // sourcery:file:Generated/{{ type.name }}
                            extension {{ type.name }} {
                            var property = 2
                            // Line Three
                            }
                            // sourcery:end
                            {% endfor %}
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())
                    }

                    it("replaces placeholder with generated code") {
                        let expectedResult = """
                            // Generated using Sourcery Major.Minor.Patch — https://github.com/krzysztofzablocki/Sourcery
                            // DO NOT EDIT
                            extension Foo {
                            var property = 2
                            // Line Three
                            }

                            """

                        let generatedPath = outputDir + Path("Generated/Foo.generated.swift")

                        let result = try? generatedPath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                    it("removes code from within generated template") {
                        let expectedResult = """
                            // Generated using Sourcery Major.Minor.Patch — https://github.com/krzysztofzablocki/Sourcery
                            // DO NOT EDIT

                            // Line One

                            """

                        let generatedPath = outputDir + Sourcery().generatedPath(for: templatePath)

                        let result = try? generatedPath.read(.utf8)
                        expect(result?.withoutWhitespaces).to(equal(expectedResult.withoutWhitespaces))
                    }

                    it("does not create generated file with empty content") {
                        update(code: """
                            {% for type in types.all %}
                            // sourcery:file:Generated/{{ type.name }}
                            // sourcery:end
                            {% endfor %}
                            """, in: templatePath)

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true, prune: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let generatedPath = outputDir + Path("Generated/Foo.generated.swift")

                        let result = try? generatedPath.read(.utf8)
                        expect(result).to(beNil())
                    }

                    it("appends content of several annotations into one file") {
                        update(code: """
                            // Line One
                            // sourcery:file:Generated/Foo
                            extension Foo {
                            var property1 = 1
                            }
                            // sourcery:end
                            // sourcery:file:Generated/Foo
                            extension Foo {
                            var property2 = 2
                            }
                            // sourcery:end
                            """, in: templatePath)

                        let expectedResult = """
                            // Generated using Sourcery Major.Minor.Patch — https://github.com/krzysztofzablocki/Sourcery
                            // DO NOT EDIT
                            extension Foo {
                            var property1 = 1
                            }

                            extension Foo {
                            var property2 = 2
                            }

                            """

                        expect { try Sourcery(watcherEnabled: false, cacheDisabled: true, prune: true).processFiles(.sources(Paths(include: [sourcePath])), usingTemplates: Paths(include: [templatePath]), output: output, baseIndentation: 0) }.toNot(throwError())

                        let generatedPath = outputDir + Path("Generated/Foo.generated.swift")

                        let result = try? generatedPath.read(.utf8)
                        expect(result).to(equal(expectedResult))
                    }

                }

                context("given a restricted file") {
                    let targetPath = outputDir + Sourcery().generatedPath(for: templatePath)

                    it("ignores files that are marked with generated by Sourcery") {
                        _ = try? targetPath.delete()

                        expect {
                            try Sourcery(cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [Stubs.resultDirectory] + Path("Basic.swift"))),
                                              usingTemplates: Paths(include: [templatePath]),
                                              output: output, baseIndentation: 0)
                            }.toNot(throwError())

                        expect(targetPath.exists).to(beFalse())
                    }

                    it("throws error when file contains merge conflict markers") {
                        let sourcePath = outputDir + Path("Source.swift")

                        update(code: """


                            <<<<<

                            """, in: sourcePath)

                        expect {
                            try Sourcery(cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [sourcePath])),
                                              usingTemplates: Paths(include: [templatePath]),
                                              output: output, baseIndentation: 0)
                            }.to(throwError())
                    }

                    it("does not throw when source file does not exist") {
                        let sourcePath = outputDir + Path("Missing.swift")
                        expect {
                            try Sourcery(cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [sourcePath])),
                                              usingTemplates: Paths(include: [templatePath]),
                                              output: Output(outputDir, linkTo: nil), baseIndentation: 0)
                            }.toNot(throwError())
                    }
                }

                context("given excluded source paths") {
                    it("ignores excluded sources") {
                        expect {
                            try Sourcery(cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [Stubs.sourceDirectory], exclude: [Stubs.sourceDirectory + "Foo.swift"])),
                                              usingTemplates: Paths(include: [templatePath]),
                                              output: output, baseIndentation: 0)
                            }.toNot(throwError())

                        let result = (try? (outputDir + Sourcery().generatedPath(for: templatePath)).read(.utf8))
                        let expectedResult = try? (Stubs.resultDirectory + Path("BasicFooExcluded.swift")).read(.utf8).withoutWhitespaces
                        expect(result.flatMap { $0.withoutWhitespaces }).to(equal(expectedResult?.withoutWhitespaces))
                    }
                }

                context("without a watcher") {
                    it("creates expected output file") {
                        expect {
                            try Sourcery(cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [Stubs.sourceDirectory])),
                                              usingTemplates: Paths(include: [templatePath]),
                                              output: output, baseIndentation: 0)
                            }.toNot(throwError())

                        let result = (try? (outputDir + Sourcery().generatedPath(for: templatePath)).read(.utf8))
                        expect(result.flatMap { $0.withoutWhitespaces }).to(equal(expectedResult?.withoutWhitespaces))
                    }
                }

#if canImport(ObjectiveC)
                context("with watcher") {
                    var watcher: Any?
                    let tmpTemplate = outputDir + Path("FakeTemplate.stencil")
                    func updateTemplate(code: String) { guard (try? tmpTemplate.write(code)) != nil else { fatalError() } }

                    it("re-generates on template change") {
                        updateTemplate(code: "Found {{ types.enums.count }} Enums")

                        expect { watcher = try Sourcery(watcherEnabled: true, cacheDisabled: true).processFiles(.sources(Paths(include: [Stubs.sourceDirectory])), usingTemplates: Paths(include: [tmpTemplate]), output: output, baseIndentation: 0) }.toNot(throwError())

                        // ! Change the template
                        updateTemplate(code: "Found {{ types.all.count }} Types")

                        let result: () -> String? = { (try? (outputDir + Sourcery().generatedPath(for: tmpTemplate)).read(.utf8)) }
                        expect(result()).toEventually(contain("\(Sourcery.generationHeader)Found 3 Types"))

                        _ = watcher
                    }
                }
#endif
            }

            context("given a template folder") {

                context("given a single file output") {
                    let outputFile = outputDir + "Composed.swift"
#if canImport(JavaScriptCore)
                    let expectedResult = try? (Stubs.resultDirectory + Path("Basic+Other+SourceryTemplates.swift")).read(.utf8).withoutWhitespaces
                    it("joins generated code into single file") {
                        expect {
                            try Sourcery(cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [Stubs.sourceDirectory])),
                                              usingTemplates: Paths(include: [
                                                Stubs.templateDirectory + "Basic.stencil",
                                                Stubs.templateDirectory + "Other.stencil",
                                                Stubs.templateDirectory + "SourceryTemplateStencil.sourcerytemplate",
                                                Stubs.templateDirectory + "SourceryTemplateEJS.sourcerytemplate"
                                              ]),
                                              output: Output(outputFile), baseIndentation: 0)
                            }.toNot(throwError())

                        let result = try? outputFile.read(.utf8)
                        expect(result?.withoutWhitespaces).to(equal(expectedResult?.withoutWhitespaces))
                    }
#else
                    let expectedResult = try? (Stubs.resultDirectory + Path("Basic+Other+SourceryTemplates_Linux.swift")).read(.utf8).withoutWhitespaces
                    it("joins generated code into single file") {
                        expect {
                            try Sourcery(cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [Stubs.sourceDirectory])),
                                              usingTemplates: Paths(include: [
                                                Stubs.templateDirectory + "Basic.stencil",
                                                Stubs.templateDirectory + "Other.stencil",
                                                Stubs.templateDirectory + "SourceryTemplateStencil.sourcerytemplate"
                                              ]),
                                              output: Output(outputFile), baseIndentation: 0)
                            }.toNot(throwError())

                        let result = try? outputFile.read(.utf8)
                        expect(result?.withoutWhitespaces).to(equal(expectedResult?.withoutWhitespaces))
                    }
#endif

                    it("does not create generated file with empty content") {
                        let templatePath = Stubs.templateDirectory + Path("Empty.stencil")
                        update(code: "", in: templatePath)

                        expect {
                            try Sourcery(cacheDisabled: true, prune: true).processFiles(.sources(Paths(include: [Stubs.sourceDirectory])),
                                                                                        usingTemplates: Paths(include: [templatePath]),
                                                                                        output: Output(outputFile), baseIndentation: 0)
                        }.toNot(throwError())

                        let result = try? outputFile.read(.utf8)
                        expect(result).to(beNil())
                    }
                }

                context("given an output directory") {
                    it("creates corresponding output file for each template") {
                        let templateNames = ["Basic", "Other"]
                        let generated = templateNames.map { outputDir + Sourcery().generatedPath(for: Stubs.templateDirectory + "\($0).stencil") }
                        let expected = templateNames.map { Stubs.resultDirectory + Path("\($0).swift") }

                        expect {
                            try Sourcery(cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [Stubs.sourceDirectory])),
                                              usingTemplates: Paths(include: [Stubs.templateDirectory]),
                                              output: output, baseIndentation: 0)
                            }.toNot(throwError())

                        for (idx, outputPath) in generated.enumerated() {
                            let output = try? outputPath.read(.utf8)
                            let expected = try? expected[idx].read(.utf8)

                            expect(output?.withoutWhitespaces).to(equal(expected?.withoutWhitespaces))
                        }
                    }
                }

                context("given excluded template paths") {
                    let outputFile = outputDir + "Composed.swift"
                    let expectedResult = try? (Stubs.resultDirectory + Path("Basic+Other.swift")).read(.utf8).withoutWhitespaces

                    it("do not create generated file for excluded templates") {
                        expect {
                            try Sourcery(cacheDisabled: true)
                                .processFiles(.sources(Paths(include: [Stubs.sourceDirectory])),
                                              usingTemplates: Paths(include: [Stubs.templateDirectory],
                                                                    exclude: [
                                                                        Stubs.templateDirectory + "GenerationWays.stencil",
                                                                        Stubs.templateDirectory + "Include.stencil",
                                                                        Stubs.templateDirectory + "Partial.stencil",
                                                                        Stubs.templateDirectory + "SourceryTemplateStencil.sourcerytemplate",
                                                                        Stubs.templateDirectory + "SourceryTemplateEJS.sourcerytemplate"
                                                                    ]),
                                              output: Output(outputFile), baseIndentation: 0)
                            }.toNot(throwError())

                        let result = try? outputFile.read(.utf8)
                        expect(result.flatMap { $0.withoutWhitespaces }).to(equal(expectedResult?.withoutWhitespaces))
                    }
                }

            }

            context("given project") {
                var originalProject: XcodeProj?

                let projectPath = Stubs.sourceDirectory + "TestProject"
                let projectFilePath = Stubs.sourceDirectory + "TestProject/TestProject.xcodeproj"
                // swiftlint:disable:next force_try
                let sources = try! Source(dict: [
                    "project": [
                        "file": "TestProject.xcodeproj",
                        "target": ["name": "TestProject"]
                    ]], relativePath: projectPath)
                var templatePath = Stubs.templateDirectory + "Other.stencil"
                var templates: Paths {
                    return Paths(include: [templatePath])
                }
                var output: Output {
                    // swiftlint:disable:next force_try
                    return try! Output(dict: [
                        "path": outputDir.string,
                        "link": ["project": "TestProject.xcodeproj", "target": "TestProject"]
                        ], relativePath: projectPath)
                }
                var sourceFilesPaths: [Path] {
                    guard let project = try? XcodeProj(path: projectFilePath),
                        let target = project.target(named: "TestProject") else {
                            return []
                    }

                    return project.sourceFilesPaths(target: target, sourceRoot: projectPath)
                }

                beforeEach {
                    expect {
                        originalProject = try XcodeProj(path: projectFilePath)
                        }.toNot(throwError())
                }

                afterEach {
                    expect {
                        try originalProject?.writePBXProj(path: projectFilePath, outputSettings: .init())
                        }.toNot(throwError())
                }

#if canImport(ObjectiveC)
                it("links generated files") {
                    expect {
                        try Sourcery(cacheDisabled: true, prune: true).processFiles(sources, usingTemplates: templates, output: output, baseIndentation: 0)
                    }.toNot(throwError())

                    expect(sourceFilesPaths.contains(outputDir + "Other.generated.swift")).to(beTrue())
                }
#endif
                it("links generated files when using per file generation") {
                    templatePath = outputDir + "PerFileGeneration.stencil"
                    update(code: """
                            // Line One
                            {% for type in types.all %}
                            // sourcery:file:Generated/{{ type.name }}.generated.swift
                            extension {{ type.name }} {
                            var property = 2
                            // Line Three
                            }
                            // sourcery:end
                            {% endfor %}
                            """, in: templatePath)

                    expect {
                        try Sourcery(cacheDisabled: true, prune: true).processFiles(sources, usingTemplates: templates, output: output, baseIndentation: 0)
                    }.toNot(throwError())

                    expect {
                        let paths = sourceFilesPaths
                        expect(paths.contains(outputDir + "PerFileGeneration.generated.swift")).to(beTrue())
                        expect(paths.contains(outputDir + "Generated/FooBarBaz.generated.swift")).to(beTrue())
                    }.toNot(throwError())
                }
            }
        }
    }
}
