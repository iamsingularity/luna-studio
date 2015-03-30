{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}

module Generator where

import Data.Set (Set)
import qualified Data.Set as Set
import Control.Monad.Trans.Class
import Control.Monad.Trans.State.Lazy
import Control.Applicative
import Text.Printf
import Language.Haskell.TH
import Language.Haskell.TH.Syntax (VarStrictType)
import qualified Language.Haskell.TH.Syntax as THS
import Language.Haskell.TH.Quote
import Data.List
import qualified Data.Set as Set
import Data.Int

import GHC.Stack
import Debug.Trace


type HeaderSource = String

type ImplementationSource = String

type CppFormattedCode = (HeaderSource, ImplementationSource)

class CppFormattablePart a where
    format :: a -> String

class CppFormattable a  where
    formatCpp :: a -> CppFormattedCode

class CppFormattableCtx a ctx | a -> ctx where
    formatCppCtx :: a -> ctx -> CppFormattedCode

--instance (CppFormattableCtx a ctx) => CppFormattableCtx [a] ctx where
--    formatCppCtx = ("", "")

data CppArg = CppArg 
    { argName :: String
    , argType :: String    
    }

instance CppFormattablePart CppArg where
    format arg = argType arg ++ " " ++ argName arg

data CppQualifier = ConstQualifier | VolatileQualifier | PureVirtualQualifier | OverrideQualifier
                    deriving (Eq)

instance CppFormattablePart CppQualifier where
    format ConstQualifier = " const"
    format VolatileQualifier = " volatile"
    format OverrideQualifier = " override"
    format PureVirtualQualifier = " = 0"

type CppQualifiers = [CppQualifier]

instance CppFormattablePart CppQualifiers where
    format qualifiers = intercalate " " $ (map format qualifiers)


data CppStorage = Usual | Static | Virtual

instance CppFormattablePart CppStorage where
    format Usual = ""
    format Static = "static "
    format Virtual = "virtual "

data CppFunction = CppFunction
    { name :: String
    , returnType :: String
    , args :: [CppArg]
    , body :: String
    }

instance CppFormattable CppFunction where
    formatCpp fn = ("function fundc", "function fdunc")

formatArgsList :: [CppArg] -> String
formatArgsList args = "(" ++ Data.List.intercalate ", " (map format args) ++ ")"

formatSignature :: CppFunction -> String
formatSignature (CppFunction name ret args _) = formatArgsList args

data CppMethod = CppMethod
    { function :: CppFunction
    , qualifiers :: CppQualifiers
    , storage :: CppStorage
    }

instance CppFormattableCtx CppMethod CppClass where
    formatCppCtx (CppMethod (CppFunction n r a b) q s) cls@(CppClass cn _ _ _ tmpl) = 
        let st = format s :: String
            rt = r :: String
            nt = n :: String
            at = formatArgsList a :: String
            qt = format q :: String
            signatureHeader = printf "\t%s%s %s%s%s;" st rt nt at qt :: String

            scope = (templateDepName cls)
            templateIntr = formatTemplateIntroductor tmpl
            qst = (format $ filter ((==) ConstQualifier) q) -- qualifiers signature text
            signatureImpl = printf "%s%s %s::%s%s %s" templateIntr rt scope nt at qst :: String
            implementation = signatureImpl ++ "\n{\n" ++ b ++ "\n}"

        in (signatureHeader, implementation)

data CppFieldSource = CppFieldSourceRec VarStrictType

data CppField = CppField 
    { fieldName :: String
    , fieldType :: String
    , source :: CppFieldSource
    }

instance CppFormattablePart CppField where
    format field = fieldType field ++ " " ++ fieldName field

instance CppFormattablePart [CppField] where
    format fields = 
        let formatField field = printf "\t%s;" (format field) -- FIXME think think think
            formattedFields = formatField <$> fields
            ret = intercalate "\n" formattedFields
        in ret

data CppAccess = Protected | Public | Private
instance CppFormattablePart CppAccess where
    format Protected = "protected"
    format Public = "public"
    format Private = "private"

data CppDerive = CppDerive
    { baseName :: String
    , isVirtual :: Bool
    , access :: CppAccess
    }

--instance CppFormattablePart CppDerive where
--    format (CppDerive base virtual access) = format access ++ " " ++ (if virtual then "virtual " else "") ++ base

--instance CppFormattablePart [CppDerive] where
--    format [] = ""
--    format derives = ": " ++ Data.List.intercalate ", " (map format derives)

data CppClass = CppClass 
    { className :: String
    , classFields :: [CppField]
    , classMethods :: [CppMethod]
    , baseClasses :: [CppDerive]
    , templateParams :: [String]
    }

cppClassTypeUse :: CppClass -> String
cppClassTypeUse cls@(CppClass name _ _ _ tmpl) = if null tmpl then name else printf "%s<%s>" name (formatTemplateArgs tmpl)

collapseCode :: [CppFormattedCode] -> CppFormattedCode
collapseCode input = (intercalate "\n" (map fst input), intercalate "\n\n" (map snd input))

instance CppFormattable CppClass where
    formatCpp cls@(CppClass name fields methods bases tmpl) = 
        let formatBase (CppDerive bname bvirt bacc) = 
                let baseTempl = if null tmpl then "" else printf "<%s>" (intercalate ", " tmpl)
                in format bacc ++ " " ++ (if bvirt then "virtual " else "") ++ bname ++ baseTempl

            basesTxt = if null bases then
                    ""
                else
                    ": " ++ intercalate ", " (formatBase <$> bases)
            fieldsTxt = format fields
            -- fff =  (formatCppCtx <$> methods <*> [cls]) :: [CppFormattedCode]
            (methodsHeader, methodsImpl) = collapseCode (formatCppCtx <$> methods <*> [cls])
            templatePreamble = formatTemplateIntroductor tmpl
            headerCode = printf "%sclass %s %s \n{\npublic:\n\tvirtual ~%s() {}\n%s\n\n%s\n};" templatePreamble name basesTxt name fieldsTxt methodsHeader
            bodyCode = methodsImpl
        in (headerCode, bodyCode)

data CppInclude = CppSystemInclude String | CppLocalInclude String
instance CppFormattable CppInclude where
    formatCpp (CppSystemInclude path) = (printf "#include <%s>" path, "")
    formatCpp (CppLocalInclude path) = (printf "#include \"%s\"" path, "")

data CppForwardDecl = CppForwardDeclClass String [String] -- | CppForwardDeclStruct String
instance CppFormattable CppForwardDecl where
    formatCpp (CppForwardDeclClass name tmpl) = (printf "%sclass %s;" (formatTemplateIntroductor tmpl) name, "")
    -- formatCpp (CppForwardDeclStruct name) = (printf "struct %s;" name, "")

data CppTypedef  = CppTypedef 
    { introducedType :: String
    , baseType :: String
    , _typedefTmpl :: [String]
    }

instance CppFormattable CppTypedef where
    formatCpp (CppTypedef to from tmpl) = 
        let templateList = formatTemplateIntroductor tmpl
        in (printf "%susing %s = %s;" templateList to from, "")

data CppParts = CppParts
    { includes :: [CppInclude]
    , forwardDecls :: [CppForwardDecl]
    , typedefs :: [CppTypedef]
    , classes :: [CppClass]
    , functions :: [CppFunction]
    }

instance CppFormattable CppParts where
    formatCpp (CppParts incl frwrds tpdefs cs fns) = 
        let includesPieces = map formatCpp incl
            forwardDeclPieces = map formatCpp frwrds
            typedefPieces = map formatCpp tpdefs
            classesCodePieces = map formatCpp cs
            functionsPieces = map formatCpp fns
            -- FIXME code duplication above

            allPieces = concat [includesPieces, forwardDeclPieces, typedefPieces, classesCodePieces, functionsPieces]

            collectCodePieces fn = Data.List.intercalate "\n\n/****************/\n\n" (map fn allPieces)
            headerCode = collectCodePieces fst
            bodyCode = collectCodePieces snd
        in (headerCode, bodyCode)

formatTemplateArgs :: [String] -> String
formatTemplateArgs tmpl = intercalate ", " (map ((++) "typename ") tmpl)

formatTemplateIntroductor :: [String] -> String
formatTemplateIntroductor tmpl = if null tmpl then "" else
                                    printf "template<%s>\n" (formatTemplateArgs tmpl) :: String

standardSystemIncludes :: [CppInclude]
standardSystemIncludes = map CppSystemInclude ["memory", "vector", "string"]

translateToCppName :: Name -> String 
translateToCppName name = nameBase name

generateRootClassWrapper :: Dec -> [CppClass] -> CppClass
generateRootClassWrapper (DataD cxt name tyVars cons names) derClasses = 
    let tnames = map tyvarToCppName tyVars
        initialCls = CppClass (translateToCppName name) [] [] [] tnames
        deserializeMethod = prepareDeserializeMethodBase initialCls derClasses
        serializeMethod = 
            let fn = CppFunction "serialize" "void" [CppArg "output" "Output &"] "assert(0); // pure virtual function"
            in CppMethod fn [PureVirtualQualifier] Virtual
    in CppClass (translateToCppName name) [] [serializeMethod, deserializeMethod] [] tnames

isValueTypeInfo :: Info -> Q Bool
isValueTypeInfo (TyConI (TySynD name vars t)) = isValueType t
isValueTypeInfo _ = return False

isValueType :: Type -> Q Bool
isValueType (VarT name) = return True
isValueType ListT = return True
isValueType (AppT base nested) = isValueType base
isValueType (ConT name) | (elem name builtInTypes) = return True
isValueType (ConT name) = do
    info <- reify name
    isValueTypeInfo info
isValueType _ = return False

templateDepNameBase :: String -> [String] -> String
templateDepNameBase clsName tmpl = if null tmpl then clsName else printf "%s<%s>" clsName $ intercalate "," tmpl

templateDepName :: CppClass -> String
templateDepName cls@(CppClass clsName _ _ _ tmpl) = templateDepNameBase clsName tmpl

typeOfField :: Type -> Q String
typeOfField t@(ConT name) = do
    let nb = nameBase name
    byValue <- isValueType t
    return $ 
        if name == ''String then "std::string" 
        else if name == ''Int then "int"
        else if name == ''Int64 then "std::int64_t"
        else if name == ''Int32 then "std::int32_t"
        else if name == ''Int16 then "std::int16_t"
        else if name == ''Int8 then "std::int8_t"
        else if byValue then nb
        else "std::shared_ptr<" ++ nb ++ ">"

typeOfField (AppT (ConT base) nested) | (base == ''Maybe) = do
    nestedName <- typeOfField nested
    isNestedValue <- isValueType nested
    return $ if isNestedValue then "boost::optional<" ++ nestedName ++ ">" else nestedName

typeOfField (AppT ListT (nested)) = do
    nestedType <- typeOfField nested
    return $ printf "std::vector<%s>" $ nestedType
--typeOfField (AppT ConT (maybe)) = printf "boost::optional<%s>" $ typeOfField nested

typeOfField (VarT n) = return $ show n

typeOfField (AppT bt@(ConT base) arg) = do
    let baseType = nameBase base
    argType <- typeOfField arg
    isBaseVal <- isValueType bt
    return $ printf (if isBaseVal then "%s<%s>" else "std::shared_ptr<%s<%s>>") baseType argType

typeOfField t = return $ trace ("FIXME: typeOfField for " ++ show t) $ "[" ++ show t ++ "]"

emptyQParts :: Q CppParts
emptyQParts = return $ CppParts [] [] []  [] []

processField :: THS.VarStrictType -> Q CppField
processField field@(name, _, t) = do
    filedType <- typeOfField t
    return $ CppField (translateToCppName name) filedType (CppFieldSourceRec field)
-- processField arg = trace ("FIXME: Field for " ++ show arg) (return $ CppField "__" "--")

deserializeFromFName = "deserializeFrom"


prepareDeserializeMethodBase :: CppClass -> [CppClass] -> CppMethod
prepareDeserializeMethodBase cls@(CppClass clsName _ _ _ tmpl) derClasses = 
    let fname = deserializeFromFName
        arg = CppArg "input" "Input &"
        rettype = printf "std::shared_ptr<%s>" $ if null tmpl then clsName 
            else templateDepName cls

        indices = [0 ..  (length derClasses)-1]
        caseForCon index =
            let ithCon =  derClasses !! index
                conName = className ithCon
            in printf "case %d: return %s::deserializeFrom(input);" index (templateDepNameBase conName tmpl) :: String

        cases = map caseForCon indices

        body =  [ "auto constructorIndex = readInt8(input);"
                , "switch(constructorIndex)"
                , "{"
                ] ++ cases ++ 
                [ "default: return nullptr;"
                , "}"
                ]

        prettyBody = intercalate "\n" (map ((++) "\t") body)

        fun = CppFunction fname rettype [arg] prettyBody
    in CppMethod fun [] Static

prepareDeserializeMethodDer :: CppClass -> CppMethod
prepareDeserializeMethodDer cls@(CppClass clsName _ _ _ tmpl)  = 
    let fname = deserializeFromFName
        clsName = className cls
        arg = CppArg "input" "Input &"
        nestedRetType = if null tmpl then clsName else templateDepName cls
        rettype = printf "std::shared_ptr<%s>" nestedRetType

        deserializeField field@(CppField fieldName fieldType fieldSrc) = printf "\tdeserialize(ret->%s, input);" fieldName :: String

        bodyOpener = printf "\tauto ret = std::make_shared<%s>();" nestedRetType :: String
        bodyCloser = "\treturn ret;"
        body = intercalate "\n" $ [bodyOpener] ++ (map deserializeField $ classFields cls) ++ [bodyCloser]

        fun = CppFunction fname rettype [arg] body
        qual = []
        stor = Static
    in CppMethod fun qual stor


processConstructor :: Dec -> Con -> Q CppClass
processConstructor dec@(DataD cxt name tyVars cons names) con@(RecC cname fields) = 
    do
        let baseCppName = translateToCppName name
            tnames = map tyvarToCppName tyVars
            derCppName = baseCppName ++ "_" ++ translateToCppName cname
        cppFields <- mapM processField fields
        let baseClasses = [CppDerive baseCppName False Public]
        let classInitial = CppClass derCppName cppFields [] baseClasses tnames
        let Just index = elemIndex con cons
        let serializeField field = printf "\t::serialize(%s, output);" (fieldName field) :: String
        let serializeCode = intercalate "\n" $ [printf "\t::serialize(std::int8_t(%d), output);" index :: String] ++ (serializeField <$> cppFields)
        let serializeFn = CppFunction "serialize" "void" [CppArg "output" "Output &"] serializeCode

        let serializeMethod = CppMethod serializeFn [OverrideQualifier] Virtual
        let methods = [serializeMethod, prepareDeserializeMethodDer classInitial]
        return $ CppClass derCppName cppFields methods baseClasses tnames
processConstructor dec arg = trace ("FIXME: Con for " ++ show arg) (return $ CppClass "" [] [] [] [])

tyvarToCppName :: TyVarBndr -> String
tyvarToCppName (PlainTV n) = show n
tyvarToCppName arg = trace ("FIXME: tyvarToCppName for " ++ show arg) $ show arg

generateCppWrapperHlp :: Dec -> Q CppParts
-- generateCppWrapperHlp arg | trace ("generateCppWrapperHlp: " ++ show arg) False = undefined
generateCppWrapperHlp dec@(DataD cxt name tyVars cons names) = 
    do
        derClasses <- sequence $ processConstructor <$> [dec] <*> cons
        let baseClass = generateRootClassWrapper dec derClasses
        -- derClasses = processConstructor <$> cons <*> [name]
        let classes = baseClass : derClasses
            functions = []
            forwardDecs = map (\c -> CppForwardDeclClass (className c) (templateParams c)) classes
        return (CppParts standardSystemIncludes forwardDecs [] classes functions)

generateCppWrapperHlp tysyn@(TySynD name tyVars rhstype) = do
    baseTName <- typeOfField rhstype
    let tnames = map tyvarToCppName tyVars
    let tf = CppTypedef (nameBase name) baseTName tnames
    return $ CppParts [] [] [tf] [] []

generateCppWrapperHlp arg = trace ("FIXME: generateCppWrapperHlp for " ++ show arg) emptyQParts


generateSingleWrapper :: Name -> Q CppParts
generateSingleWrapper arg | trace ("generateSingleWrapper: " ++ show arg) False = undefined
generateSingleWrapper name = do
    nameInfo <- reify name
    let bb = case nameInfo of
            (TyConI dec) -> generateCppWrapperHlp dec
            _ -> trace ("ignoring entry " ++ show name) emptyQParts
    bb

joinParts :: [CppParts] -> CppParts
joinParts parts = 
    CppParts (concat $ map includes parts) (concat $ map forwardDecls parts) (concat $ map typedefs parts) (concat $ map classes parts) (concat $ map functions parts)

generateWrappers :: [Name] -> Q CppParts
generateWrappers names = do
    let partsWithQ = map generateSingleWrapper names
    parts <- sequence partsWithQ
    return $ joinParts parts

generateWrapperWithDeps :: Name -> Q CppParts
generateWrapperWithDeps name = do
    relevantNames <- collectDependencies name
    generateWrappers relevantNames


formatCppWrapper :: Name -> Q CppFormattedCode
formatCppWrapper arg | trace ("formatCppWrapper: " ++ show arg) False = undefined
formatCppWrapper name = do
    parts <- generateWrapperWithDeps name
    return $ formatCpp parts


builtInTypes = [''Maybe, ''String, ''Int, ''Int32, ''Int64, ''Int16, ''Int8]

class TypesDependencies a where
    symbolDependencies :: a -> Set Name

instance TypesDependencies Type where
    --symbolDependencies t | trace ("Type: " ++ show t) False = undefined

    -- Maybe and String are handled as a special-case
    symbolDependencies (ConT name) | (elem name builtInTypes) = Set.empty
    symbolDependencies contype@(ConT name) = Set.singleton name
    symbolDependencies apptype@(AppT ListT nested) = symbolDependencies nested
    symbolDependencies apptype@(AppT base nested) = symbolDependencies [base, nested]
    symbolDependencies vartype@(VarT n) = Set.empty
    symbolDependencies t = trace ("FIXME not handled type: " ++ show t) Set.empty

instance (TypesDependencies a, Show a) => TypesDependencies [a] where
    --symbolDependencies t | trace ("list: " ++ show t) False = undefined
    symbolDependencies listToProcess =
        let listOfSets = (map symbolDependencies listToProcess)::[Set Name]
        in Set.unions listOfSets

instance TypesDependencies (Strict, Type) where
    symbolDependencies (_, t) = symbolDependencies t

instance TypesDependencies Con where
    --symbolDependencies t | trace ("Con: " ++ show t) False = undefined
    symbolDependencies (RecC name fields) = symbolDependencies fields
    symbolDependencies (NormalC name fields) = symbolDependencies fields
    symbolDependencies t = trace ("FIXME not handled Con: " ++ show t) (errorWithStackTrace) []

instance TypesDependencies VarStrictType where
    --symbolDependencies t | trace ("Field: " ++ show t) False = undefined
    symbolDependencies (_, _, t) = symbolDependencies t

instance TypesDependencies Info where
--    symbolDependencies t | trace ("Info: " ++ show t) False = undefined
    symbolDependencies (TyConI (DataD _ n _ cons _)) = symbolDependencies cons
    symbolDependencies (TyConI (TySynD n _ t)) = symbolDependencies t
    symbolDependencies arg = trace ("FIXME not handled Info: " ++ show arg) (Set.empty)

blah :: Name -> StateT [Name] Q [Name]
blah name = do
    nameInfo <- lift $ reify name
    return []

additionalDependencies :: Set Name -> Info -> Set Name
additionalDependencies alreadyKnownDeps queriedInfo = 
    let allDepsOfInfo = symbolDependencies queriedInfo
        newDeps = Set.difference alreadyKnownDeps allDepsOfInfo
    in newDeps

collectDirectDependencies :: Name -> Q [Name]
-- collectDirectDependencies name | trace ("collectDirectDependencies " ++ show name) False = undefined
collectDirectDependencies name = do
    nameInfo <- reify name
    let namesSet = symbolDependencies nameInfo
    return $ Set.elems namesSet
    -- evalStateT (blah name) []

naiveBfs :: [Name] -> [Name] -> Q [Name]
-- naiveBfs q d | trace (show q ++ "\n\n" ++ show d) False = undefined
naiveBfs [] discovered = return discovered
naiveBfs queue discovered = do
    let vertex = head queue
    neighbours <- collectDirectDependencies vertex
    let neighboursToAdd = filter (flip notElem discovered) neighbours
    let newQueue = tail queue ++ neighboursToAdd
    let newDiscovered = discovered ++ neighboursToAdd
    naiveBfs newQueue newDiscovered

collectDependencies :: Name -> Q [Name]
collectDependencies name = do
    let queue = [name]
    let discovered = [name]
    naiveBfs queue discovered

printAst :: Info -> String
printAst  (TyConI dec@(DataD cxt name tyVars cons names)) = 
    let namesShown = (Prelude.map show names) :: [String]
        consCount = Data.List.length cons :: Int
        ret = ("cxt=" ++ show cxt ++ "\nname=" ++ show name ++ "\ntyVars=" ++ show tyVars ++ "\ncons=" ++ show cons ++ "\nnames=" ++ show names) :: String
    in show consCount ++ "___" ++ ret

generateCpp :: Name -> FilePath -> Q Exp
generateCpp name path = do
    let headerName = path ++ ".h"
    let cppName = path ++ ".cpp"

    dependencies <- collectDependencies name
    runIO (putStrLn $ printf "Found %d dependencies: %s" (length dependencies) (show dependencies))
    (header,body) <- formatCppWrapper name


    runIO (writeFile headerName header)
    runIO (writeFile cppName body)

    runIO (writeFile cppName $ (printf "#include \"helper.h\"\n#include \"%s\"\n\n" headerName) ++ body)
    [|  return () |]

