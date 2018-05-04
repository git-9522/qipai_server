#include <iterator>
#include <set>
#include <string>
#include <vector>
#include <map>
#include <fstream>
#include <string.h>
#include <lua.hpp>

namespace utf8
{
    // The typedefs for 8-bit, 16-bit and 32-bit unsigned integers
    // You may need to change them to match your system.
    // These typedefs have the same names as ones from cstdint, or boost/cstdint
    typedef unsigned char   uint8_t;
    typedef unsigned short  uint16_t;
    typedef unsigned int    uint32_t;

// Helper code - not intended to be directly called by the library users. May be changed at any time
namespace internal
{
    // Unicode constants
    // Leading (high) surrogates: 0xd800 - 0xdbff
    // Trailing (low) surrogates: 0xdc00 - 0xdfff
    const uint16_t LEAD_SURROGATE_MIN  = 0xd800u;
    const uint16_t LEAD_SURROGATE_MAX  = 0xdbffu;
    const uint16_t TRAIL_SURROGATE_MIN = 0xdc00u;
    const uint16_t TRAIL_SURROGATE_MAX = 0xdfffu;
    const uint16_t LEAD_OFFSET         = LEAD_SURROGATE_MIN - (0x10000 >> 10);
    const uint32_t SURROGATE_OFFSET    = 0x10000u - (LEAD_SURROGATE_MIN << 10) - TRAIL_SURROGATE_MIN;

    // Maximum valid value for a Unicode code point
    const uint32_t CODE_POINT_MAX      = 0x0010ffffu;

    template<typename octet_type>
    inline uint8_t mask8(octet_type oc)
    {
        return static_cast<uint8_t>(0xff & oc);
    }
    template<typename u16_type>
    inline uint16_t mask16(u16_type oc)
    {
        return static_cast<uint16_t>(0xffff & oc);
    }
    template<typename octet_type>
    inline bool is_trail(octet_type oc)
    {
        return ((utf8::internal::mask8(oc) >> 6) == 0x2);
    }

    template <typename u16>
    inline bool is_lead_surrogate(u16 cp)
    {
        return (cp >= LEAD_SURROGATE_MIN && cp <= LEAD_SURROGATE_MAX);
    }

    template <typename u16>
    inline bool is_trail_surrogate(u16 cp)
    {
        return (cp >= TRAIL_SURROGATE_MIN && cp <= TRAIL_SURROGATE_MAX);
    }

    template <typename u16>
    inline bool is_surrogate(u16 cp)
    {
        return (cp >= LEAD_SURROGATE_MIN && cp <= TRAIL_SURROGATE_MAX);
    }

    template <typename u32>
    inline bool is_code_point_valid(u32 cp)
    {
        return (cp <= CODE_POINT_MAX && !utf8::internal::is_surrogate(cp));
    }

    template <typename octet_iterator>
    inline typename std::iterator_traits<octet_iterator>::difference_type
    sequence_length(octet_iterator lead_it)
    {
        uint8_t lead = utf8::internal::mask8(*lead_it);
        if (lead < 0x80)
            return 1;
        else if ((lead >> 5) == 0x6)
            return 2;
        else if ((lead >> 4) == 0xe)
            return 3;
        else if ((lead >> 3) == 0x1e)
            return 4;
        else
            return 0;
    }

    template <typename octet_difference_type>
    inline bool is_overlong_sequence(uint32_t cp, octet_difference_type length)
    {
        if (cp < 0x80) {
            if (length != 1) 
                return true;
        }
        else if (cp < 0x800) {
            if (length != 2) 
                return true;
        }
        else if (cp < 0x10000) {
            if (length != 3) 
                return true;
        }

        return false;
    }

    enum utf_error {UTF8_OK, NOT_ENOUGH_ROOM, INVALID_LEAD, INCOMPLETE_SEQUENCE, OVERLONG_SEQUENCE, INVALID_CODE_POINT};

    /// Helper for get_sequence_x
    template <typename octet_iterator>
    utf_error increase_safely(octet_iterator& it, octet_iterator end)
    {
        if (++it == end)
            return NOT_ENOUGH_ROOM;

        if (!utf8::internal::is_trail(*it))
            return INCOMPLETE_SEQUENCE;
        
        return UTF8_OK;
    }

    #define UTF8_CPP_INCREASE_AND_RETURN_ON_ERROR(IT, END) {utf_error ret = increase_safely(IT, END); if (ret != UTF8_OK) return ret;}    

    /// get_sequence_x functions decode utf-8 sequences of the length x
    template <typename octet_iterator>
    utf_error get_sequence_1(octet_iterator& it, octet_iterator end, uint32_t& code_point)
    {
        if (it == end)
            return NOT_ENOUGH_ROOM;

        code_point = utf8::internal::mask8(*it);

        return UTF8_OK;
    }

    template <typename octet_iterator>
    utf_error get_sequence_2(octet_iterator& it, octet_iterator end, uint32_t& code_point)
    {
        if (it == end) 
            return NOT_ENOUGH_ROOM;
        
        code_point = utf8::internal::mask8(*it);

        UTF8_CPP_INCREASE_AND_RETURN_ON_ERROR(it, end)

        code_point = ((code_point << 6) & 0x7ff) + ((*it) & 0x3f);

        return UTF8_OK;
    }

    template <typename octet_iterator>
    utf_error get_sequence_3(octet_iterator& it, octet_iterator end, uint32_t& code_point)
    {
        if (it == end)
            return NOT_ENOUGH_ROOM;
            
        code_point = utf8::internal::mask8(*it);

        UTF8_CPP_INCREASE_AND_RETURN_ON_ERROR(it, end)

        code_point = ((code_point << 12) & 0xffff) + ((utf8::internal::mask8(*it) << 6) & 0xfff);

        UTF8_CPP_INCREASE_AND_RETURN_ON_ERROR(it, end)

        code_point += (*it) & 0x3f;

        return UTF8_OK;
    }

    template <typename octet_iterator>
    utf_error get_sequence_4(octet_iterator& it, octet_iterator end, uint32_t& code_point)
    {
        if (it == end)
           return NOT_ENOUGH_ROOM;

        code_point = utf8::internal::mask8(*it);

        UTF8_CPP_INCREASE_AND_RETURN_ON_ERROR(it, end)

        code_point = ((code_point << 18) & 0x1fffff) + ((utf8::internal::mask8(*it) << 12) & 0x3ffff);

        UTF8_CPP_INCREASE_AND_RETURN_ON_ERROR(it, end)

        code_point += (utf8::internal::mask8(*it) << 6) & 0xfff;

        UTF8_CPP_INCREASE_AND_RETURN_ON_ERROR(it, end)

        code_point += (*it) & 0x3f;

        return UTF8_OK;
    }

    #undef UTF8_CPP_INCREASE_AND_RETURN_ON_ERROR

    template <typename octet_iterator>
    utf_error validate_next(octet_iterator& it, octet_iterator end, uint32_t& code_point)
    {
        // Save the original value of it so we can go back in case of failure
        // Of course, it does not make much sense with i.e. stream iterators
        octet_iterator original_it = it;

        uint32_t cp = 0;
        // Determine the sequence length based on the lead octet
        typedef typename std::iterator_traits<octet_iterator>::difference_type octet_difference_type;
        const octet_difference_type length = utf8::internal::sequence_length(it);

        // Get trail octets and calculate the code point
        utf_error err = UTF8_OK;
        switch (length) {
            case 0: 
                return INVALID_LEAD;
            case 1:
                err = utf8::internal::get_sequence_1(it, end, cp);
                break;
            case 2:
                err = utf8::internal::get_sequence_2(it, end, cp);
            break;
            case 3:
                err = utf8::internal::get_sequence_3(it, end, cp);
            break;
            case 4:
                err = utf8::internal::get_sequence_4(it, end, cp);
            break;
        }

        if (err == UTF8_OK) {
            // Decoding succeeded. Now, security checks...
            if (utf8::internal::is_code_point_valid(cp)) {
                if (!utf8::internal::is_overlong_sequence(cp, length)){
                    // Passed! Return here.
                    code_point = cp;
                    ++it;
                    return UTF8_OK;
                }
                else
                    err = OVERLONG_SEQUENCE;
            }
            else 
                err = INVALID_CODE_POINT;
        }

        // Failure branch - restore the original value of the iterator
        it = original_it;
        return err;
    }

    template <typename octet_iterator>
    inline utf_error validate_next(octet_iterator& it, octet_iterator end) {
        uint32_t ignored;
        return utf8::internal::validate_next(it, end, ignored);
    }

} // namespace internal

    /// The library API - functions intended to be called by the users

    // Byte order mark
    const uint8_t bom[] = {0xef, 0xbb, 0xbf};

    template <typename octet_iterator>
    octet_iterator find_invalid(octet_iterator start, octet_iterator end)
    {
        octet_iterator result = start;
        while (result != end) {
            utf8::internal::utf_error err_code = utf8::internal::validate_next(result, end);
            if (err_code != internal::UTF8_OK)
                return result;
        }
        return result;
    }

    template <typename octet_iterator>
    inline bool is_valid(octet_iterator start, octet_iterator end)
    {
        return (utf8::find_invalid(start, end) == end);
    }

    template <typename octet_iterator>
    inline bool starts_with_bom (octet_iterator it, octet_iterator end)
    {
        return (
            ((it != end) && (utf8::internal::mask8(*it++)) == bom[0]) &&
            ((it != end) && (utf8::internal::mask8(*it++)) == bom[1]) &&
            ((it != end) && (utf8::internal::mask8(*it))   == bom[2])
           );
    }
	
    //Deprecated in release 2.3 
    template <typename octet_iterator>
    inline bool is_bom (octet_iterator it)
    {
        return (
            (utf8::internal::mask8(*it++)) == bom[0] &&
            (utf8::internal::mask8(*it++)) == bom[1] &&
            (utf8::internal::mask8(*it))   == bom[2]
           );
    }
} // namespace utf8

struct SGFilterFinderNode;
typedef std::map<unsigned int, SGFilterFinderNode*> SGFilterFinderNodeMap;
typedef SGFilterFinderNodeMap::iterator SGFilterFinderNodeIter;

struct SGFilterFinderNode
{
	~SGFilterFinderNode()
	{
		for (SGFilterFinderNodeIter iter = m_mapFinderNode.begin();
			iter != m_mapFinderNode.end(); ++iter)
		{
			delete iter->second;
		}
	}

	SGFilterFinderNodeMap m_mapFinderNode;
};


class SGTextFilter
{
	friend class SGRevisionSensitiveWord;
public:
	SGTextFilter();
	~SGTextFilter();

	int LoadFiles(const char* pSensitiveWordPath, const char* pWhiteWordPath);

	bool HasSensitiveWords(char *pText, int iLength);
	char* ReplaceSensitiveWords(char *pText, int iLength);

	int TraceEx();

protected:
	int LoadFile(const char* pPath, SGFilterFinderNode* pRoot);
	inline bool Search(const char* pcStr, const char* pcEndStr, int &iLength,const SGFilterFinderNode* pNode);
	int TraceEx(std::string strPrevChar, SGFilterFinderNode* pNode);

private:

	inline const char* Advance(const char* pcCharSequence, unsigned int& uiDWord);
	void InsertWords(const char* pcWords, int iWordsSize, SGFilterFinderNode* pNode);

protected:
	SGFilterFinderNode m_stSensitiveRoot;
	SGFilterFinderNode m_stInsensitiveRoot;
};


class SGRevisionSensitiveWord
{
	struct LegalTextRecord
	{
		std::string m_strLegalText;
		int m_iBegin;
		LegalTextRecord(std::string strLegalText, int iBegin) :
			m_strLegalText(strLegalText), m_iBegin(iBegin)
		{
		}
	};

	struct RevisionString
	{
		char* m_pStr;
		int m_iLength;
		RevisionString(char *pStr, int iLength) :
			m_pStr(pStr), m_iLength(iLength)
		{
		}
	};

	std::vector<LegalTextRecord> m_vecLegalTextRecord;
	char *m_pcRowText;
	int m_iRowTextLength;
	bool m_bHasSensitive;
	SGTextFilter* m_pFilter;
public:

	SGRevisionSensitiveWord(char* pRowText, int iRowTextLength, SGTextFilter* pFilter) :
		m_pcRowText(pRowText), m_iRowTextLength(iRowTextLength), m_bHasSensitive(false), m_pFilter(pFilter)
	{
	}

	bool HasSensitiveWord()
	{
		m_bHasSensitive = false;
		if (!CheckOrReplace(true))
		{
			return true;
		}
		return m_bHasSensitive;
	}

	bool ReplaceSensitiveWord()
	{
		return CheckOrReplace();
	}

    char* GetReplaceWorld()
    {
        return m_pcRowText;
    }

protected:
	bool CheckOrReplace(bool bJustLook = false);

	bool OnFindInsensitiveWords(RevisionString strWords);
	bool OnFindSensitiveWords(RevisionString strWords);
	bool OnFindSensitiveWordsCheck(RevisionString strWords);

	typedef bool (SGRevisionSensitiveWord::*pFindHandler)(RevisionString);

	void Foreach(const SGFilterFinderNode* pNode, pFindHandler pFunc);
	void RecoverWhiteWords();
};

bool SGRevisionSensitiveWord::OnFindInsensitiveWords(RevisionString strWords)
{
	//这个是白名单的字，存上
	std::string strMatch(strWords.m_pStr, strWords.m_iLength);
	LegalTextRecord stRecord(strMatch,strWords.m_pStr - m_pcRowText);
	m_vecLegalTextRecord.push_back(stRecord);
	//把白名单的字给替换掉，免得黑名单发现它
	memset(strWords.m_pStr, '#', strWords.m_iLength);
	return true;
}

bool SGRevisionSensitiveWord::OnFindSensitiveWords(RevisionString strWords)
{
	memset(strWords.m_pStr, '*', strWords.m_iLength);
	return true;
}

bool SGRevisionSensitiveWord::OnFindSensitiveWordsCheck(RevisionString strWords)
{
	m_bHasSensitive = true;
	return false;
}

void SGRevisionSensitiveWord::Foreach(const SGFilterFinderNode* pNode, pFindHandler pFunc)
{
	int iCurrLength = 0;
	while (iCurrLength < m_iRowTextLength)
	{
		char *pcStartChar = m_pcRowText + iCurrLength;
		char *pcEndChar = m_pcRowText + m_iRowTextLength;

		int iMatchLength = 0;
		if (m_pFilter->Search(pcStartChar, pcEndChar, iMatchLength, pNode))
		{
			RevisionString strMatched(pcStartChar, iMatchLength);
			if (!(this->*pFunc)(strMatched))
			{
				return;
			}
		}

		iCurrLength += utf8::internal::sequence_length(pcStartChar);
	}
}


void SGRevisionSensitiveWord::RecoverWhiteWords()
{
	for (size_t i = 0; i < m_vecLegalTextRecord.size(); i++)
	{
		const LegalTextRecord& stRecord = m_vecLegalTextRecord[i];
		memcpy(m_pcRowText + stRecord.m_iBegin, stRecord.m_strLegalText.c_str(), stRecord.m_strLegalText.size());
	}
}


bool SGRevisionSensitiveWord::CheckOrReplace(bool bJustLook /*= false*/)
{
	if (utf8::starts_with_bom(m_pcRowText, m_pcRowText + m_iRowTextLength))
	{
		return false;
	}

	if (!utf8::is_valid(m_pcRowText, m_pcRowText + m_iRowTextLength))
	{
		return false;
	}

	//先替换掉白名单
	Foreach(&m_pFilter->m_stInsensitiveRoot, &SGRevisionSensitiveWord::OnFindInsensitiveWords);

	if (bJustLook)
	{
		Foreach(&m_pFilter->m_stSensitiveRoot, &SGRevisionSensitiveWord::OnFindSensitiveWordsCheck);
	}
	else
	{
		Foreach(&m_pFilter->m_stSensitiveRoot, &SGRevisionSensitiveWord::OnFindSensitiveWords);
	}

	//再替换回白名单
	RecoverWhiteWords();

	return true;
}


SGTextFilter::SGTextFilter()
{

}


SGTextFilter::~SGTextFilter()
{

}

const char* SGTextFilter::Advance(const char* pcCharSequence, unsigned int& uiDWord)
{
	uiDWord = 0;
	int iLength = utf8::internal::sequence_length(pcCharSequence);
	memcpy(&uiDWord, pcCharSequence, iLength);
	return pcCharSequence + iLength;
}


void SGTextFilter::InsertWords(const char* pcWords, int iWordsSize, SGFilterFinderNode* pNode)
{
	if (iWordsSize <= 0)
	{
		return;
	}

	unsigned int uiWords;
	const char* pcEnd = pcWords + iWordsSize;

	while (pcWords < pcEnd)
	{
		pcWords = Advance(pcWords, uiWords);
		SGFilterFinderNode*& pTmpNode = pNode->m_mapFinderNode[uiWords];
		if (!pTmpNode)
		{
			pTmpNode = new SGFilterFinderNode;
		}
		pNode = pTmpNode;
	}
	pNode->m_mapFinderNode[0] = NULL;
}

int SGTextFilter::LoadFile(const char* pPath, SGFilterFinderNode* pRoot)
{
	std::ifstream fs(pPath, std::fstream::in | std::fstream::binary);
	if (!fs)
	{
		return -1;
	}
	fs.seekg(0, fs.end);
	int iLength = fs.tellg();
	fs.seekg(0, fs.beg);

	char *pContent = new char[iLength];
	fs.read(pContent, iLength);
	if (!fs)
	{
		delete[] pContent;
		return -2;
	}

	fs.close();

	//检查一个是不是合法的UTF8文本文件
	if (utf8::starts_with_bom(pContent, pContent + iLength))
	{
		delete[] pContent;
		return -3;
	}

	if (!utf8::is_valid(pContent, pContent + iLength))
	{
		delete[] pContent;
		return -4;
	}

	std::string strWords;
	strWords.reserve(512);

	for (int i = 0; i < iLength; i++)
	{
		if (pContent[i] == ',')
		{
			InsertWords(strWords.c_str(), strWords.size(), pRoot);
			strWords.clear();
			continue;
		}

		strWords.push_back(pContent[i]);
	}
	if (!strWords.empty())
	{
		InsertWords(strWords.c_str(), strWords.size(), pRoot);
	}

	delete[] pContent;
	
	return 0;
}

int SGTextFilter::LoadFiles(const char* pSensitiveWordPath, const char* pWhiteWordPath)
{
	int iRet = LoadFile(pSensitiveWordPath, &m_stSensitiveRoot);
	if (iRet)
	{
		return -1;
	}
	// iRet = LoadFile(pWhiteWordPath, &m_stInsensitiveRoot);
	// if (iRet)
	// {
	// 	return -2;
	// }

	return 0;
}

//////////////////////////////////////////////////////////////////////////
bool SGTextFilter::Search(const char* pcStr, const char* pcEndStr, int &iLength, const SGFilterFinderNode* pNode)
{
	iLength = 0;
	const char* pTempStr = pcStr;
	while (pcStr < pcEndStr)
	{
		SGFilterFinderNodeMap::const_iterator iter = pNode->m_mapFinderNode.find(0);
		if (iter != pNode->m_mapFinderNode.end())
		{
			iLength = pcStr - pTempStr;
		}

		unsigned int uiWords;
		pcStr = Advance(pcStr, uiWords);

		iter = pNode->m_mapFinderNode.find(uiWords);
		if (iter == pNode->m_mapFinderNode.end())
		{
			//已经找不到了，看看前面有没有过完整串，有的话则以找到前面的串为主,没有的话就没得匹配
			return iLength > 0;
		}

		//找到字符则继续看下一个字符
		pNode = iter->second;
	}

	if (pNode->m_mapFinderNode.find(0) != pNode->m_mapFinderNode.end())
	{
		iLength = pcStr - pTempStr;
		return true;
	}

	return iLength > 0;
}

bool SGTextFilter::HasSensitiveWords(char *pText, int iLength)
{
	SGRevisionSensitiveWord stRevision(pText, iLength,this);
	return stRevision.HasSensitiveWord();
}

char* SGTextFilter::ReplaceSensitiveWords(char *pText, int iLength)
{
	SGRevisionSensitiveWord stRevision(pText, iLength, this);
	stRevision.ReplaceSensitiveWord();
    return stRevision.GetReplaceWorld();
}


///////////////////////////////////////////////////
static const char* GetCharacter(unsigned int uiDWord)
{
	int iLen = utf8::internal::sequence_length((char*)&uiDWord);
	static char acTempBuff[12];
	memcpy(acTempBuff, &uiDWord, iLen);
	acTempBuff[iLen] = 0;
	return acTempBuff;
}

int SGTextFilter::TraceEx(std::string strPrevChar, SGFilterFinderNode* pNode)
{
	if (!pNode)
	{
		//输出(*os) << strPrevChar << "\n";
		return 0;
	}
	SGFilterFinderNodeIter iter = pNode->m_mapFinderNode.begin();
	for (; iter != pNode->m_mapFinderNode.end(); ++iter)
	{
		std::string strTemp = strPrevChar + GetCharacter(iter->first);
		TraceEx(strTemp, iter->second);
	}
	return 0;
}

int SGTextFilter::TraceEx()
{
	TraceEx("", &m_stSensitiveRoot);
	return 0;
}

////=====================================LUA INTERFACE============================
static int 
linit(lua_State *L)
{
	const char* path = luaL_checkstring(L,1);
	SGTextFilter* filter = new SGTextFilter();
	int ret = filter->LoadFiles(path, "");
	if(ret){
		return 0;
	}
	lua_pushlightuserdata(L,filter);
	return 1;
}

static int 
lis_sensitive(lua_State *L)
{
	SGTextFilter* filter = reinterpret_cast<SGTextFilter*>(lua_touserdata(L,1));
	size_t length = 0;
	const char* words = luaL_checklstring(L,2,&length);

	char buffer[4096];
	if (length >= sizeof(buffer))
	{
		lua_pushboolean(L, 1);
		return 1;
	}

	memcpy(buffer, words, length);
	lua_pushboolean(L, filter->HasSensitiveWords(buffer, length));
	return 1;
}

static int 
lreplace_sensitive(lua_State *L)
{
    SGTextFilter* filter = reinterpret_cast<SGTextFilter*>(lua_touserdata(L,1));
    size_t length = 0;
    const char* words = luaL_checklstring(L,2,&length);

    char buffer[4096];
    if (length >= sizeof(buffer))
    {
        lua_pushboolean(L, 1);
        return 1;
    }

    memcpy(buffer, words, length);
    filter->ReplaceSensitiveWords(buffer, length);

    char tmp_str[length+1];
    memcpy(tmp_str,buffer,length);
    tmp_str[length] = 0;
    
    lua_pushstring(L, tmp_str);
    return 1;
}

extern "C" int
luaopen_textfilter(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "init", linit },
		{ "is_sensitive", lis_sensitive },
        { "replace_sensitive", lreplace_sensitive },
		{ NULL, NULL },
	};
	luaL_newlib(L,l);

	return 1;
}
