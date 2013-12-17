#include <fstream>

#include "generated/server-api.pb.h"
#include <boost/algorithm/string.hpp>

#ifdef _WIN32
#pragma comment(lib, "libprotobuf.lib")
#endif


using namespace generated::proto::batch;
using namespace google::protobuf;


void formatOutput(std::ostream &out, std::string contents)
{
	auto hlp = contents;
	boost::replace_all(hlp, "\t", "");
	int count = 0;
	std::string outtxt;
	for(int i = 0; i < hlp.size(); i++)
	{
		const char &c = hlp[i];

		if(c == '}'  &&  outtxt.back() == '\t') outtxt.pop_back();

		outtxt.push_back(c);
		if(c == '{') count++;
		else if(c == '}') count--;
		else if(c == '\n') for(int j = 0; j < count; j++) outtxt.push_back('\t');

	}

	out << outtxt;
}


const std::string headerFile = R"(
#include <string>
#include <vector>
#include <boost/optional.hpp>
#include <boost/asio.hpp>

#include "../BatchIdWrappers.h"

class %wrapper_name%
{
public:
std::function<void(const std::string&)> before;
std::function<void(const std::string&)> success;
std::function<void(const std::string&)> error;
std::function<void(const std::string&)> after;


generated::proto::crumb::Breadcrumbs crumbify(DefinitionId defID);

size_t sendAll(void *data, size_t size);
void sendRequest(const generated::proto::batch::Request& request);
generated::proto::batch::Response receiveResponse();
generated::proto::batch::Response call(const generated::proto::batch::Request& request);
generated::proto::batch::Response callAndTranslateException(const generated::proto::batch::Request& request);

boost::asio::ip::tcp::socket &socket;
%wrapper_name%(boost::asio::ip::tcp::socket &socket) : socket(socket) {}
%method_decls%
};
)";

const std::string sourceFile = R"(

#include "BatchClient.h"

#include <google/protobuf/io/zero_copy_stream_impl.h>
#include <google/protobuf/io/coded_stream.h>


const int BUFFER_SIZE = 10000000; // TODO [PM] : magic constant

using boost::asio::ip::tcp;
using Socket = tcp::socket;

size_t %wrapper_name%::sendAll(void *data, size_t size)
{
	size_t sent = boost::asio::write(socket, boost::asio::buffer(data, size));
	assert(sent == size);
	return sent;
}


void %wrapper_name%::sendRequest(const generated::proto::batch::Request& request)
{
	int  requestSize = request.ByteSize() + 4;
	std::vector<char> requestBuf(requestSize, 0);
	//char* requestBuf = new char[requestSize];

	//write varint delimiter to buffer
	google::protobuf::io::ArrayOutputStream arrayOut(requestBuf.data(), requestSize);
	google::protobuf::io::CodedOutputStream codedOut(&arrayOut);
	codedOut.WriteVarint32(request.ByteSize());

	//write protobuf ack to buffer
	request.SerializeToCodedStream(&codedOut);

	//send buffer to client
	sendAll(requestBuf.data(), requestSize);
	// std::cout << "Sent: " << sent << std::flush;

	//delete [] requestBuf;
}

generated::proto::batch::Response %wrapper_name%::receiveResponse()
{
	static char buffer[BUFFER_SIZE];

	generated::proto::batch::Response response;
	size_t received = boost::asio::read(socket, boost::asio::buffer(buffer, 4));

	//read varint delimited protobuf object in to buffer
	//there's no method to do this in the C++ library so here's the workaround
	google::protobuf::io::ArrayInputStream headerArrayIn(buffer, received);
	google::protobuf::io::CodedInputStream headerCodedIn(&headerArrayIn);
	google::protobuf::uint32 packetSize;
	headerCodedIn.ReadVarint32(&packetSize);
	const int sizeinfoLength = headerCodedIn.CurrentPosition();
	const int remainingToRead = packetSize + sizeinfoLength - received;

	received = boost::asio::read(socket, boost::asio::buffer(buffer + received, remainingToRead));

	google::protobuf::io::ArrayInputStream arrayIn(buffer + sizeinfoLength, packetSize);
	google::protobuf::io::CodedInputStream codedIn(&arrayIn);
	google::protobuf::io::CodedInputStream::Limit msgLimit = codedIn.PushLimit(packetSize);
	response.ParseFromCodedStream(&codedIn);
	codedIn.PopLimit(msgLimit);
	return response;
}

generated::proto::batch::Response %wrapper_name%::call(const generated::proto::batch::Request& request)
{
	sendRequest(request);
	return receiveResponse();
}

generated::proto::batch::Response %wrapper_name%::callAndTranslateException(const generated::proto::batch::Request& request)
{
	auto response = call(request);

	if(response.type() == generated::proto::batch::Response_Type_Exception)
	{
		const auto exc = response.GetExtension(generated::proto::batch::Exception::rsp);
		const auto msg = exc.message();
		throw std::runtime_error(msg);
	}

	return response;
}

%method_impls%
)";

const std::string methodDeclaration = "%rettype% %space%_%method%(%args_list%);";

const std::string methodDefinition = R"(
%rettype% %wrapper_name%::%space%_%method%(%args_list%)
{
	if(before) before("%space%_%method%");
	FINALIZE{ if(after) after("%space%_%method%"); };
	try
	{
		
		generated::proto::batch::%space%_%method%_Args *args = new generated::proto::batch::%space%_%method%_Args();
		%setters%

		generated::proto::batch::Request request;
		request.set_method(generated::proto::batch::Request_Method_%space%_%method%);
		request.SetAllocatedExtension(generated::proto::batch::%space%_%method%_Args::req, args);

		generated::proto::batch::Response response = callAndTranslateException(request);
		assert(response.type() == generated::proto::batch::Response_Type_Result); //exception would be translated to exception

		FINALIZE{ if(success) success("%space%_%method%"); };
		%epilogue%
	}
	catch(std::exception &e)
	{
		if(error) error("%space%_%method%");
		std::string msg = std::string("Call to batch method %space%::%method% triggered an exception: ") + e.what();
		throw std::runtime_error(msg);
	}
}
)";

struct ArgWrapper
{
	const FieldDescriptor *arg;

	ArgWrapper(const FieldDescriptor*arg) :arg(arg) {}

	std::string translateBaseType(bool stripRef = false) const
	{
		FieldDescriptor::Type type = arg->type();
		switch(type)
		{
		case FieldDescriptor::TYPE_DOUBLE:
			return "double";
		case FieldDescriptor::TYPE_BOOL:
			return "bool";
		case FieldDescriptor::TYPE_INT32:
			return "int";
		case FieldDescriptor::TYPE_STRING:
		case FieldDescriptor::TYPE_BYTES:
			return stripRef ? "std::string" : "const std::string &";
		case FieldDescriptor::TYPE_MESSAGE:
		{
			auto ret = arg->message_type()->full_name();
			boost::replace_all(ret, ".", "::");
			return ret;
		}
		default:
			assert(0);
		}

		assert(0);
		return {};
	}

	std::string translateType(bool asValue = false) const
	{
		std::string ret;
		if(arg->is_repeated())
		{
			if(asValue)
				ret = "std::vector<%2>";
			else
				ret = "const std::vector<%2> &";
		}
		else if(arg->is_optional())
		{
			if(asValue)
				ret = "boost::optional<%2>";
			else
				ret = "const boost::optional<%2> &";
		}
		else if(arg->type() == FieldDescriptor::TYPE_MESSAGE)
		{
			if(asValue)
				ret = "%1";
			else
				ret = "const %1 &";
		}
		else
			ret = "%1";

		boost::replace_all(ret, "%1", translateBaseType(false));
		boost::replace_all(ret, "%2", translateBaseType(true));
		return ret;
	}

	std::string formatArgument() const
	{
		return translateType() + " " + arg->name();
	}
};

struct MethodWrapper
{
	std::vector<const FieldDescriptor*> argsFields;
	const Descriptor *args, *result;
	const EnumValueDescriptor *methodValue;

	std::string space, name;

	std::string returnedType, epilogue, arguments, setters;

	std::vector<int> collapsedArgs;
	std::string collapsedName; 

	MethodWrapper(const FileDescriptor *file, const EnumValueDescriptor *method) : methodValue(method)
	{
		std::vector<std::string> parts;
		boost::split(parts, methodValue->name(), boost::is_any_of("_"));
		assert(parts.size() == 2);
		space = parts[0];
		name = parts[1];

		auto spaceDescriptor = file->FindMessageTypeByName(parts[0]);
		auto methodDescriptor = spaceDescriptor->FindNestedTypeByName(parts[1]);

		args = methodDescriptor->FindNestedTypeByName("Args");
		result = methodDescriptor->FindNestedTypeByName("Result");
		for(int i = 0; i < args->field_count(); i++)
			argsFields.push_back(args->field(i));

		arguments = translateArguments();
		setters = formatSetters();
		formatEpilogue();
	}

	std::string format(const std::string &input) const
	{
		auto ret = input;
		boost::replace_all(ret, "%space%", space);
		boost::replace_all(ret, "%method%", name);
		boost::replace_all(ret, "%args_list%", arguments);
		boost::replace_all(ret, "%setters%", setters);
		boost::replace_all(ret, "%epilogue%", epilogue);
		boost::replace_all(ret, "%rettype%", returnedType);
		//boost::replace_all(ret, "%rettype%", returnedType);
		return ret;
	}

	std::string formatDecl() const
	{
		return format(methodDeclaration);
	}

	std::string formatImpl() const
	{
		return format(methodDefinition);
	}

	std::string translateArguments() 
	{
		std::vector<std::string> argsTxt;
		for(int i = 0; i < argsFields.size(); i++)
		{
			auto &arg = argsFields.at(i);
			if(arg->name() == "nodeID")
			{
				assert(argsFields.at(i + 1)->name() == "bc");
				assert(argsFields.at(i + 2)->name() == "libraryID");
				assert(argsFields.at(i + 3)->name() == "projectID");
				collapsedArgs.resize(4, i);
				i += 3;
				argsTxt.push_back("const NodeId &nodeID");
				collapsedName = "nodeID";
			}
			else if(arg->name() == "bc" || arg->name() == "parentbc")
			{
				assert(argsFields.at(i + 1)->name() == "libraryID");
				assert(argsFields.at(i + 2)->name() == "projectID");
				collapsedArgs.resize(3, i);
				i += 2;

				if(arg->name() == "bc")
					collapsedName = "defID";
				else
					collapsedName = "parent";
				argsTxt.push_back("const DefinitionId &" + collapsedName);
			}
			else if(arg->name() == "libraryID")
			{
				assert(argsFields.at(i + 1)->name() == "projectID");
				collapsedArgs.resize(2, i);
				i += 1;

				collapsedName = "libID";
				argsTxt.push_back("const LibraryId &libID");
			}
			else if(arg->name() == "projectID")
			{
				collapsedArgs.resize(1, i);
				collapsedName = "projID";
				argsTxt.push_back("const ProjectId &projID");
			}
			else
			{
				argsTxt.push_back(ArgWrapper(arg).formatArgument());
			}
		}

		return boost::join(argsTxt, ", ");
	}

	std::string formatSetters() const
	{
		std::string ret;
		for(int i = 0; i < argsFields.size(); i++)
		{
			auto &arg = argsFields.at(i);
			if(collapsedArgs.size() && collapsedArgs.front() == i)
			{
				for(int j = 0; j < collapsedArgs.size(); j++)
				{
					auto &argInner = argsFields.at(i+j);

					static const std::string names[] = { "nodeID", "defID", "libID", "projID" };
					int index = 4-collapsedArgs.size()+j;
					auto derefedArg = collapsedName + "." + names[index];
					if(index == 1)
					{
						ret += "args->mutable_" + argInner->lowercase_name() + "()->CopyFrom(crumbify(" + collapsedName + "));\n";
					}
					else
						ret += "args->set_" + argInner->lowercase_name() + "(" + derefedArg + ");\n";
				}
				i += collapsedArgs.size() - 1;
			}
			else
			{
				std::string entry;
				if(arg->is_repeated())
				{
					if(arg->type() == FieldDescriptor::TYPE_MESSAGE)
					{
						entry =
							R"(for(size_t i = 0; i < %1.size(); i++)
								{
									auto added = args->add_%2();
									added->MergeFrom(*args);
									delete args;
								})";
					}
					else
					{
						entry =
							R"(	for(size_t i = 0; i < %1.size(); i++)
										{
									      args->set_%2(i, %1.at(i));
										})";
					}
				}
				else if(arg->is_optional())
					entry = "if(%1)\n{\nargs->set_%2(*%1);\n}";
				else if(arg->type() == FieldDescriptor::TYPE_MESSAGE)
					entry = "args->mutable_%2()->CopyFrom(%1);";
				else
					entry = "args->set_%2(%1);";

				boost::replace_all(entry, "%1", arg->name());
				boost::replace_all(entry, "%2", arg->lowercase_name());
				ret += entry + "\n";
			}
		}
		return ret;
	}

	void formatEpilogue()
	{
		auto resultPack = "generated::proto::batch::" + space + "_" + name + "_Result";
		if(result->field_count() == 0)
		{
			returnedType = "void";
			epilogue = "return;";
		}
		else if(result->field_count() == 1)
		{
			auto field = result->field(0);
			returnedType = ArgWrapper(result->field(0)).translateType(true);
			epilogue = resultPack + " result = response.GetExtension(" + resultPack + "::rsp);\n";
			
			if(field->is_repeated())
			{
				epilogue += returnedType + " ret;\n";
				epilogue += "for(int i = 0; i < result."+field->lowercase_name()+"_size(); i++)\n{\n";
				epilogue += "ret.push_back(result."+field->lowercase_name()+"(i));\n}\n";
				epilogue += "return ret;";
			}
			else
			{
				epilogue += "return result." + field->lowercase_name() + "();";
			}
		}
		else
		{
			returnedType = "generated::proto::batch::" + space + "_" + name + "_Result";
			epilogue = "return response.GetExtension(" + returnedType + "::rsp);";
		}
	}
};


void generate(const std::string &outputFile)
{
	std::string methodImpls;
	std::string methodDecls;

	auto fileDescriptor = AST::descriptor()->file();
	auto methodsDescriptor = Request::Method_descriptor();
	for(int i = 0; i < methodsDescriptor->value_count(); i++)
	{
		methodImpls += MethodWrapper(fileDescriptor, methodsDescriptor->value(i)).formatImpl();
		methodDecls += MethodWrapper(fileDescriptor, methodsDescriptor->value(i)).formatDecl() + "\n";
	}

	auto formatFile = [&](const std::string &input) -> std::string
	{
		auto ret = input;
		boost::replace_all(ret, "%method_decls%", methodDecls);
		boost::replace_all(ret, "%method_impls%", methodImpls);
		boost::replace_all(ret, "%wrapper_name%", "BatchClient");
		return ret;
	};

	{
		std::ofstream out(outputFile + ".cpp");
		formatOutput(out, formatFile(sourceFile));
	}
	{
		std::ofstream out(outputFile + ".h");
		formatOutput(out, formatFile(headerFile));
	}

	for(int i = 0; i < fileDescriptor->message_type_count(); i++)
	{
		auto messageDescriptor = fileDescriptor->message_type(i);
		int g = 4;
	}
}

int main()
{
	generate("generated/BatchClient");
	return EXIT_SUCCESS;
}